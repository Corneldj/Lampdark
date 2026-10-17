extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-09 (Gameplay §3.6, §10.3): no relax blocks the pit's turn. With the engine caught and a relax
## on, the woken Moth still commits to a lamp in its sight on the road, and the Tapper at the rock
## beyond the arches still opens a hunt on a miner talking there.

const A = preload("res://tests/scenario/apex/apex_world.gd")
const D = preload("res://tests/scenario/director/draught_world.gd")
const M = preload("res://tests/scenario/creatures/moth_awake_world.gd")
const T = preload("res://tests/scenario/creatures/hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _world(run_seed: int) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": A.E.T.C.scenario_fixture(), "overrides": A.ON, "director": true})
	var gate: Gate = A.world(s, 120)
	D.stand_in(s)
	return [s, gate]


func test_the_moth_commits_to_a_light_in_a_relax() -> void:
	var w: Array = _world(9201)
	var s: Scenario = w[0]
	var gate: Gate = w[1]
	var m: Moth = A.moth(s, A.on_road(gate, 70))
	var ann: MinerHandle = M.lit_miner(s, "ann", A.on_road(gate, 45))
	D.force_relax(s, true)
	s.step(2)
	assert_true(Variants.flag(s.run.creatures.gate.relax_active.call()), "a relax")
	A.catch_now(s)
	assert_gte(M.until_state(s, m, &"hunt", 800), 0, "it hunts the lamp in its sight, relax or not")
	assert_eq(int(Variants.number(m.awake.target.get("miner", 0))), ann.entity_id)


func test_the_tapper_hunts_at_the_arches_in_a_relax() -> void:
	var w: Array = _world(9202)
	var s: Scenario = w[0]
	var gate: Gate = w[1]
	var t: Tapper = A.tapper(s, A.in_rock(gate, 40, 5))
	D.force_relax(s, true)
	s.step(2)
	A.catch_now(s)
	var end: Vector2 = t.apex_point.call()
	assert_true(s.run_until(func(sc: Scenario) -> bool: return t.position(sc.run).distance_to(end) < 12.0, 1200), "at the rock beyond the arches")
	var bob: MinerHandle = s.add_miner("bob", A.on_road(gate, 16))
	s.step(2)
	T.talk(s, bob)
	assert_gt(T.until_state(s, t, &"approach", 40), -1, "a chosen Approach goes ahead in the relax")
