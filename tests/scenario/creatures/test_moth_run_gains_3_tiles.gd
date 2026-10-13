extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-04: a miner running for 6 s ahead of a hunting Moth gains 3 ± 0.1 tiles (5.5 against 5.0
## tiles/s): running only delays it.

const A = preload("res://tests/scenario/creatures/moth_awake_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_run() -> void:
	var s: Scenario = make({"seed": 70, "fixture": A.road(140)})
	var m: Moth = A.awake(s, Vector2i(8, 2), true)
	# Close enough that she stays inside its 20-tile sight while she runs.
	var ann: MinerHandle = A.lit_miner(s, "ann", Vector2i(22, 2))
	s.step(20)
	assert_eq(m.state.name, &"hunt", "the Moth is coming at full pace")
	# A full 6 s run from rest, measured from her first step.
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.RUN, 120)
	var start_x: float = s.run.registry.get_entity(ann.entity_id).position.x
	while s.run.registry.get_entity(ann.entity_id).position.x == start_x:
		s.step(1)
	var g0: float = start_x - m.position(s.run).x + (s.run.registry.get_entity(ann.entity_id).position.x - start_x)
	s.step(119)
	var g1: float = s.run.registry.get_entity(ann.entity_id).position.x - m.position(s.run).x
	var gained: float = g1 - g0
	gut.p("6 s of running gained %.3f tiles (moth still %s)" % [gained, m.state.name])
	assert_eq(m.state.name, &"hunt", "it kept her in sight the whole run")
	assert_almost_eq(gained, 3.0, 0.1)
