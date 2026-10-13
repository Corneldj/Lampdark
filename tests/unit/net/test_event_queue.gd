extends "res://tests/scenario/kit/scenario_test.gd"
## NET-04's event queue: every event reaches its listener once, through loss; illusions append
## before numbering and never after.

const N = preload("res://tests/scenario/net/net04_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_every_event_arrives_once_through_loss() -> void:
	var s: Scenario = make({"seed": 46, "fixture": N.road()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	ann.link(120, 10.0)
	var ids: Array[int] = []
	for t: int in 100:
		if t % 4 == 0:
			ids.append(s.run.noise.emit(NoiseTypes.Type.ROCK_TAP, Vector2i(10, 2)))
		s.step()
	s.step(60)
	var got: Array[Dictionary] = s.client(ann).audio_events(0, 1000)
	assert_eq(got.size(), ids.size(), "%d events, each received once, through 10%% loss" % ids.size())
	var numbers: Array[int] = []
	for e: Dictionary in got:
		numbers.append(int(Variants.number(e["number"])))
	numbers.sort()
	for i: int in numbers.size():
		assert_eq(numbers[i], i + 1, "numbered 1 to n with no gap")
	for e: Dictionary in got:
		assert_gte(int(Variants.number(e["arrived"])), int(Variants.number(e["start_tick"])), "late at worst, keeping its start tick")


## A system after the send stage that tries to append an illusion: too late.
class LateAppender:
	extends SimSystem
	var slot: int = 0

	func stage() -> int:
		return StageTable.Stage.RECORD

	func order() -> int:
		return 50

	func system_name() -> String:
		return "late_appender"

	func tick(run: RunState) -> void:
		if run.tick == 3:
			run.replication.append_illusion_event(slot, {"type": NoiseTypes.Type.ROCK_TAP, "start_tick": run.tick,
				"apparent": Vector2(10, 2), "remaining_np": 2.0, "duration_s": 0.5})


func test_illusions_after_the_frames_are_refused() -> void:
	var late: LateAppender = LateAppender.new()
	var s: Scenario = make({"seed": 47, "fixture": N.road(), "systems": [late]})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	late.slot = ann.slot
	s.step(5)
	assert_push_error("already built")
	assert_eq(s.client(ann).audio_events(0, 100).size(), 0, "and nothing was appended")
