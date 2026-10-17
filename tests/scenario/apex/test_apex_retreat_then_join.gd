extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-09 (Gameplay §3.6, §7.1): a creature retreating when the engine catches is unaffected until
## its 120 s end, then turns toward base camp: the Tapper keeps to its retreat and then comes to the
## rock beyond the arches; the Moth sleeps on through its retreat, then stirs and prowls for the gates.

const A = preload("res://tests/scenario/apex/apex_world.gd")
const MW = preload("res://tests/scenario/creatures/moth_awake_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _world(run_seed: int) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": A.E.T.C.scenario_fixture(), "overrides": A.ON})
	var gate: Gate = A.world(s, 120)
	return [s, gate]


func _retreat_ticks() -> int:
	return roundi(Tuning.f(&"creatures.retreat_s") * Tuning.f(&"net.tick_hz"))


func test_the_tapper_retreats_then_joins() -> void:
	var w: Array = _world(9401)
	var s: Scenario = w[0]
	var gate: Gate = w[1]
	var t: Tapper = A.tapper(s, A.in_rock(gate, 70, 5))
	s.step(3)
	s.run.creatures.begin_retreat(s.run, t, "revolver")
	s.step(10)
	A.catch_now(s)
	var end: Vector2 = t.apex_point.call()
	var from: float = t.position(s.run).distance_to(end)
	var ends_at: int = t.retreat_until
	assert_gt(ends_at, s.run.tick)
	assert_true(s.run_until(func(sc: Scenario) -> bool: return sc.run.tick >= ends_at - 1, _retreat_ticks()))
	assert_true(t.is_retreating(), "still retreating, the apex no matter")
	assert_eq(t.state.name, &"retreat")
	assert_gt(t.position(s.run).distance_to(end), from - 2.0, "not drawn to the arches meanwhile")
	s.step(3)
	assert_false(t.is_retreating())
	var joined: bool = false
	for e: Dictionary in s.run.creatures.log.entries:
		joined = joined or (e["type"] == &"retreat_ended" and Variants.flag(e.get("toward_base", false)))
	assert_true(joined, "its retreat ended toward base camp")
	assert_true(s.run_until(func(sc: Scenario) -> bool: return t.position(sc.run).distance_to(end) < 12.0, 1600), "then it came to the arches")


func test_the_moth_sleeps_through_its_retreat_then_wakes() -> void:
	var w: Array = _world(9402)
	var s: Scenario = w[0]
	var gate: Gate = w[1]
	var m: Moth = A.moth(s, A.on_road(gate, 80))
	s.step(3)
	s.run.creatures.begin_retreat(s.run, m, "flare")
	s.step(5)
	A.catch_now(s)
	var ends_at: int = m.retreat_until
	assert_true(s.run_until(func(sc: Scenario) -> bool: return sc.run.tick >= ends_at - 1, _retreat_ticks()))
	assert_true(m.is_sleeping(), "asleep through its retreat")
	s.step(3)
	assert_eq(m.state.name, &"stirring", "its retreat over, the engine stirs it")
	assert_gte(MW.until_state(s, m, &"prowl", 60), 0, "and it prowls")
	assert_eq(m.rose_for, "engine")
