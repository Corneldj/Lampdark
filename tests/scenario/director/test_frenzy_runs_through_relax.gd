extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-02: a Frenzy is a consequence (Gameplay §10.3): a Moth hunting in Frenzy when a relax begins
## keeps hunting; the prowl after it commits to nothing until the build.

const D = preload("res://tests/scenario/director/draught_world.gd")
const A = preload("res://tests/scenario/creatures/moth_awake_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_frenzy_keeps_hunting_through_a_relax() -> void:
	var s: Scenario = make({"seed": 1701, "fixture": A.hall(), "director": true})
	var m: Moth = A.awake(s, Vector2i(5, 10), true)
	A.lit_miner(s, "ann", Vector2i(25, 10))
	D.stand_in(s)
	assert_gt(A.until_state(s, m, &"hunt", 200), -1, "the Frenzy hunts the light")
	var gate: HuntGate = s.run.creatures.gate
	D.force_relax(s, true)
	for _i: int in 20:
		s.step(1)
		assert_true(gate.is_hunting(m), "the relax never ends a Frenzy's hunt")
	# Spent, it prowls, and in the relax commits to nothing.
	gate.stand_down(s.run, m, "test")
	m.awake.frenzy_left = 0
	m.enter(s.run, &"prowl", "test")
	var chosen: Array[bool] = []
	gate.hunt_started.connect(func(_c: Creature, _miner: int, ch: bool) -> void: chosen.append(ch))
	s.step(100)
	assert_false(chosen.has(true), "the prowl after it commits to nothing in the relax")
