extends "res://tests/scenario/kit/scenario_test.gd"
## NET-06 at 60, 120 and 200 ms: against the Moth (stubbed until CRT-04), a shutter stamped by
## the end E that reaches the server within 150 ms after it saves the carrier, though the shutter
## only closes 0.2 s later. At 120 ms a shutter pressed 150 ms or more before the end on the
## carrier's screen always saves them.

const L = preload("res://tests/scenario/net/lagcomp_world.gd")
const E: int = 40


func before_all() -> void:
	assert_true(Tuning.load_server())


func _case(rtt_ms: int, press: int) -> Dictionary:
	var s: Scenario = make({"seed": 700 + press, "fixture": L.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"), {"facing_deg": 0.0})
	ann.link(rtt_ms, 0.0)
	var lamp: L.StubLamp = L.StubLamp.new(ann.slot, true)
	assert_true(s.run.add_system(lamp))
	var w: DefenderRule.WindUp = DefenderRule.WindUp.new()
	w.kind = &"moth"
	w.defender_slot = ann.slot
	w.defender_entity = ann.entity_id
	w.started_tick = E - 20
	w.in_reach = func(_r: RunState) -> bool: return true
	w.lit = func(_r: RunState, shut: bool) -> bool: return lamp.open and not shut
	assert_true(s.run.add_system(L.StubWindUp.new(w, E)))
	var shutter: L.FirstInput = L.FirstInput.new(ann.slot, func(c: InputBuffer.Consumed) -> bool: return (c.record.desired & 1) != 0)
	s.on_tick = func(sc: Scenario) -> void: shutter.watch(sc.run)
	ann.at(press).lamp(true, 1)
	s.step(E + 20)
	return {"stamp": shutter.stamp, "applied": shutter.applied, "outcome": w.outcome, "decided": w.decided_tick,
		"issued": w.shutter_issued}


func _sweep(rtt_ms: int) -> void:
	var saved: int = 0
	var smothered: int = 0
	for press: int in range(E - 8, E + 10):
		var r: Dictionary = _case(rtt_ms, press)
		var stamp: int = r["stamp"]
		var applied: int = r["applied"]
		var outcome: DefenderRule.Outcome = r["outcome"]
		var decided: int = r["decided"]
		assert_gte(applied, 0, "the shutter reached the server")
		var should_save: bool = stamp <= E and applied <= E + 3
		gut.p("%d ms: shutter stamped %+d, applied %+d: %s at %+d" % [rtt_ms, stamp - E, applied - E,
			DefenderRule.Outcome.keys()[outcome], decided - E])
		assert_eq(outcome, DefenderRule.Outcome.MISSED if should_save else DefenderRule.Outcome.CONFIRMED,
			"%d ms, shutter stamped %+d and applied %+d" % [rtt_ms, stamp - E, applied - E])
		assert_lte(decided, E + 3)
		if rtt_ms == 120 and stamp <= E - 3:
			assert_eq(outcome, DefenderRule.Outcome.MISSED, "120 ms: pressed 150 ms or more before the end, always saved")
		if should_save:
			saved += 1
		else:
			smothered += 1
	assert_gt(saved, 0)
	assert_gt(smothered, 0)


func test_at_60_ms() -> void:
	_sweep(60)


func test_at_120_ms() -> void:
	_sweep(120)


func test_at_200_ms() -> void:
	_sweep(200)


func test_saved_by_the_press_not_the_close() -> void:
	# At 120 ms a press stamped 3 ticks before the end arrives about 2 after it; the lamp is still
	# burning for 4 more ticks, so only the issued press can save the carrier.
	var r: Dictionary = _case(120, E - 1)
	var stamp: int = r["stamp"]
	var applied: int = r["applied"]
	var issued: bool = r["issued"]
	gut.p("120 ms: shutter stamped %+d, applied %+d, still open at the decision" % [stamp - E, applied - E])
	assert_lte(stamp, E)
	assert_gt(applied + 4, E + 3, "the shutter closes after the hold ends")
	assert_true(issued, "issued by the end")
	var outcome: DefenderRule.Outcome = r["outcome"]
	assert_eq(outcome, DefenderRule.Outcome.MISSED)
