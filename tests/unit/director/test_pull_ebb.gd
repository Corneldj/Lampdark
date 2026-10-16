extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-03's ebb (Gameplay §10.5): when any hunt on a miner ends (CRT-01's hunt_ended), whatever its
## outcome, their Pull drops by 30 once, clamped at 0.

const D = preload("res://tests/scenario/director/draught_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_30_once_whatever_the_outcome_clamped_at_0() -> void:
	var s: Scenario = make({"seed": 2301, "fixture": D.hall(), "director": true})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	D.stand_in(s)
	var c: int = s.place_stand_in(WorldIds.EntityKind.STYTHE, Vector2i(40, 3))
	var st: Creature = s.run.creatures.creature_of(c)
	var gate: HuntGate = s.run.creatures.gate
	s.step(2)
	for reason: String in ["it lost them", "driven off", "retreat", "the grab ended", "relax"]:
		assert_true(s.run.pull.set_value(ann.entity_id, 50.0))
		assert_true(gate.request_commit(s.run, st, ann.entity_id, false))
		gate.stand_down(s.run, st, reason)
		assert_almost_eq(s.run.pull.value_of(ann.entity_id), 20.0, 1e-6, "%s: -30 once" % reason)
	gate.stand_down(s.run, st, "again") # no hunt: no second ebb
	assert_almost_eq(s.run.pull.value_of(ann.entity_id), 20.0, 1e-6, "one end, one ebb")
	assert_true(s.run.pull.set_value(ann.entity_id, 10.0))
	assert_true(gate.request_commit(s.run, st, ann.entity_id, false))
	gate.stand_down(s.run, st, "x")
	assert_eq(s.run.pull.value_of(ann.entity_id), 0.0, "clamped at 0")
