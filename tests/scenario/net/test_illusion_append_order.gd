extends "res://tests/scenario/kit/scenario_test.gd"
## NET-04: an illusion appended at the illusion stage is encoded exactly as a real event: swap
## which of two events is the illusion, and the client receives the same bytes.

const N = preload("res://tests/scenario/net/net04_world.gd")


## A stand-in for CRT-10's illusion stage (stage 14): appends one event to one client.
class IllusionStub:
	extends SimSystem
	var slot: int = 0
	var event: Dictionary = {}
	var at_tick: int = 5

	func stage() -> int:
		return StageTable.Stage.ILLUSIONS

	func order() -> int:
		return 0

	func system_name() -> String:
		return "illusion_stub"

	func tick(run: RunState) -> void:
		if run.tick == at_tick and not event.is_empty():
			run.replication.append_illusion_event(slot, event)


func before_all() -> void:
	assert_true(Tuning.load_server())


## The client record a real tap at `tile` produces for Ann (seed and order fixed).
func _real_record(tile: Vector2i) -> Dictionary:
	var s: Scenario = make({"seed": 50, "fixture": N.road()})
	s.add_miner("ann", s.fixture.spot("a"))
	s.step(5)
	var got: Array[Dictionary] = []
	s.run.noise.player_hooks.append(func(_l: int, record: Dictionary, _audit: Dictionary = {}) -> void: got.append(record))
	s.run.noise.emit(NoiseTypes.Type.ROCK_TAP, tile)
	s.step(1)
	assert_eq(got.size(), 1)
	var r: Dictionary = got[0]
	# The whole client record (SND-03's AudioRecord): an illusion copies every field a real one has.
	return AudioRecord.from_delivery(r).to_event()


## One run: a real tap at `real_tile`, and an illusion carrying exactly what a real tap at the
## other tile would have delivered. Returns the event records Ann received, as bytes.
func _events_bytes(real_tile: Vector2i, illusion: Dictionary) -> PackedByteArray:
	var stub: IllusionStub = IllusionStub.new()
	var s: Scenario = make({"seed": 50, "fixture": N.road(), "systems": [stub]})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	stub.slot = ann.slot
	stub.event = illusion
	s.step(5)
	s.run.noise.emit(NoiseTypes.Type.ROCK_TAP, real_tile)
	s.step(3)
	var out: PackedByteArray = PackedByteArray()
	for e: Dictionary in s.client(ann).audio_events(0, 100):
		var keys: Array = e.keys()
		keys.sort()
		for k: Variant in keys:
			if str(k) != "arrived":
				out.append_array(var_to_bytes(e[k]))
	return out


func test_order_and_numbering_do_not_depend_on_which_is_the_illusion() -> void:
	var at_6: Dictionary = _real_record(Vector2i(6, 2))
	var at_8: Dictionary = _real_record(Vector2i(8, 2))
	var p6: Vector2 = at_6["apparent"]
	var p8: Vector2 = at_8["apparent"]
	assert_ne(p6, p8)
	var a: PackedByteArray = _events_bytes(Vector2i(6, 2), at_8)  # the tap at 8 is the illusion
	var b: PackedByteArray = _events_bytes(Vector2i(8, 2), at_6)  # the tap at 6 is the illusion
	assert_gt(a.size(), 0)
	assert_eq(a, b, "identical event records, order and numbers")
