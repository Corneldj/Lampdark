extends "res://tests/scenario/kit/scenario_test.gd"
## NET-06 at 60, 120 and 200 ms: a Tapper strike (stubbed until CRT-09) misses when the target's
## step out of reach is stamped by the end E and reaches the server within 150 ms after it; it
## lands when the step is stamped after E. The press time is swept across the end.

const L = preload("res://tests/scenario/net/lagcomp_world.gd")
const E: int = 40
const REACH: float = 1.0


func before_all() -> void:
	assert_true(Tuning.load_server())


func _case(rtt_ms: int, press: int) -> Dictionary:
	var s: Scenario = make({"seed": 600 + press, "fixture": L.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"), {"facing_deg": 0.0})
	ann.link(rtt_ms, 0.0)
	var start: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	var tapper_at: Vector2 = start - Vector2(0.95, 0.0)
	var w: DefenderRule.WindUp = DefenderRule.WindUp.new()
	w.kind = &"tapper"
	w.defender_slot = ann.slot
	w.defender_entity = ann.entity_id
	w.started_tick = E - 10
	var id: int = ann.entity_id
	w.in_reach = func(r: RunState) -> bool: return r.registry.get_entity(id).position.distance_to(tapper_at) <= REACH
	assert_true(s.run.add_system(L.StubWindUp.new(w, E)))
	var step: L.FirstInput = L.FirstInput.new(ann.slot, func(c: InputBuffer.Consumed) -> bool: return c.record.move_dir != InputRecord.NO_DIRECTION)
	s.on_tick = func(sc: Scenario) -> void: step.watch(sc.run)
	ann.at(press).move(0.0, InputRecord.Gait.WALK, 12)
	s.step(E + 20)
	return {"stamp": step.stamp, "applied": step.applied, "outcome": w.outcome, "decided": w.decided_tick}


func _sweep(rtt_ms: int) -> void:
	var escapes: int = 0
	var lands: int = 0
	var after: int = 0
	for press: int in range(E - 8, E + 10):
		var r: Dictionary = _case(rtt_ms, press)
		var stamp: int = r["stamp"]
		var applied: int = r["applied"]
		var outcome: DefenderRule.Outcome = r["outcome"]
		var decided: int = r["decided"]
		assert_gte(applied, 0, "the step reached the server")
		var should_escape: bool = stamp <= E and applied <= E + 3
		gut.p("%d ms: step stamped %+d, applied %+d (T - S %d ticks): %s at %+d" % [rtt_ms, stamp - E, applied - E,
			applied - stamp, DefenderRule.Outcome.keys()[outcome], decided - E])
		assert_eq(outcome, DefenderRule.Outcome.MISSED if should_escape else DefenderRule.Outcome.CONFIRMED,
			"%d ms, step stamped %+d and applied %+d" % [rtt_ms, stamp - E, applied - E])
		assert_lte(decided, E + 3, "decided no later than E + 150 ms")
		if should_escape:
			escapes += 1
		else:
			lands += 1
		if stamp > E:
			after += 1
			assert_eq(outcome, DefenderRule.Outcome.CONFIRMED, "a step stamped after the end never saves")
	assert_gt(escapes, 0, "%d ms: some steps escaped" % rtt_ms)
	assert_gt(lands, 0, "%d ms: some strikes landed" % rtt_ms)
	assert_gt(after, 0, "%d ms: steps stamped after the end were tried" % rtt_ms)


func test_at_60_ms() -> void:
	_sweep(60)


func test_at_120_ms() -> void:
	_sweep(120)


func test_at_200_ms() -> void:
	_sweep(200)
