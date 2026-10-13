extends "res://tests/scenario/kit/scenario_test.gd"
## NET-06's 'Now!' at 60, 120 and 200 ms round trips and over a 250 ms one-way link: the crank's
## clank (a real ENGINE_CRANK event) reaches the presser, whose client presents it on its shown
## timeline and reports when; a throttle press 0.9 s after the clank on the presser's screen
## counts, and one at 1.1 s backfires (LFT-04 owns the job; this stubs its cue and press).

const L = preload("res://tests/scenario/net/lagcomp_world.gd")
const C: int = 30


class StubCue:
	extends SimSystem
	var slot: int
	var tile: Vector2i
	var cue: int = 0

	func _init(miner_slot: int, at: Vector2i) -> void:
		slot = miner_slot
		tile = at

	func stage() -> int:
		return StageTable.Stage.WORLD

	func order() -> int:
		return 90

	func system_name() -> String:
		return "StubCue"

	func tick(run: RunState) -> void:
		if run.tick == C:
			run.noise.emit(NoiseTypes.Type.ENGINE_CRANK, tile)
			cue = run.now_judge.register_cue(slot, NoiseTypes.Type.ENGINE_CRANK, C)


func before_all() -> void:
	assert_true(Tuning.load_server())


func _press_after(rtt_ms: int, seconds: float) -> Dictionary:
	var s: Scenario = make({"seed": 900 + rtt_ms, "fixture": L.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	ann.link(rtt_ms, 0.0)
	var stub: StubCue = StubCue.new(ann.slot, s.fixture.spot("a"))
	assert_true(s.run.add_system(stub))
	var press: L.FirstInput = L.FirstInput.new(ann.slot, func(c: InputBuffer.Consumed) -> bool: return (c.record.holds & InputRecord.HOLD_INTERACT) != 0)
	s.on_tick = func(sc: Scenario) -> void: press.watch(sc.run)
	var offset: float = seconds * Tuning.f(&"net.tick_hz")
	var pressed: bool = false
	for i: int in 120:
		s.step(1)
		if pressed or ann.connection.cues.presented.is_empty():
			continue
		var p: PackedInt64Array = ann.connection.cues.presented[0]
		var arrived: float = float(p[1]) + p[2] / 256.0
		var stamp: PackedInt64Array = ann.connection.shown_stamp(Transport.now_usec())
		# The next input leaves during the next step, about a tick on.
		if float(stamp[0]) + stamp[1] / 256.0 + 1.0 >= arrived + offset:
			ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 4)
			pressed = true
	var window: float = Tuning.f(&"lift.now_window_s") * Tuning.f(&"net.tick_hz")
	var presented: PackedInt64Array = ann.connection.cues.presented[0]
	var a: float = s.run.now_judge.displayed_tick_of(ann.slot, stub.cue)
	return {"cue": stub.cue, "presented": presented, "a": a, "stamp": press.stamp, "applied": press.applied,
		"verdict": s.run.now_judge.judge(ann.slot, stub.cue, float(press.stamp), window)}


func _both(rtt_ms: int) -> void:
	for seconds: float in [0.9, 1.1]:
		var r: Dictionary = _press_after(rtt_ms, seconds)
		var presented: PackedInt64Array = r["presented"]
		var a: float = r["a"]
		var stamp: int = r["stamp"]
		var applied: int = r["applied"]
		var verdict: NowJudge.Verdict = r["verdict"]
		gut.p("%d ms RTT: clank at %d presented at %d; press %.1f s later stamped %d (+%.2f s), applied at %d: %s" % [
			rtt_ms, C, presented[1], seconds, stamp, (stamp - a) / 20.0, applied, NowJudge.Verdict.keys()[verdict]])
		var cue: int = r["cue"]
		assert_eq(presented[0], cue, "the client named the cue as the server did")
		assert_almost_eq(a, float(presented[1]) + presented[2] / 256.0, 1e-9, "the server took the client's report")
		assert_eq(verdict, NowJudge.Verdict.ON_TIME if seconds < 1.0 else NowJudge.Verdict.LATE,
			"%d ms: a press %.1f s after the clank on screen" % [rtt_ms, seconds])


func test_at_60_ms() -> void:
	_both(60)


func test_at_120_ms() -> void:
	_both(120)


func test_at_200_ms() -> void:
	_both(200)


func test_over_a_250_ms_one_way_link() -> void:
	_both(500)
