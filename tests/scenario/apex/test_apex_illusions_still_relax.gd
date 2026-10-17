extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-09 (Gameplay §10.3): illusions are not hunts, so the apex never frees them. With the engine
## caught, a relax still stops every illusion (DIR-02's gate, which CRT-10 and CRT-11 read), while the
## creatures' hunts go ahead; out of the relax they may play again.

const A = preload("res://tests/scenario/apex/apex_world.gd")
const D = preload("res://tests/scenario/director/draught_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_illusions_stop_in_a_relax_during_the_apex() -> void:
	var s: Scenario = make({"seed": 9701, "fixture": A.E.T.C.scenario_fixture(), "overrides": A.ON, "director": true})
	A.world(s, 60)
	D.stand_in(s)
	s.step(2)
	A.catch_now(s)
	assert_true(s.run.apex.active)
	D.force_relax(s, true)
	s.step(2)
	assert_true(Variants.flag(s.run.creatures.gate.relax_active.call()), "a relax, in the apex")
	assert_false(s.run.relax.illusions_allowed(), "no illusion plays")
	assert_true(Variants.flag(s.run.creatures.gate.apex_on.call()), "while hunts ignore the relax")
	D.force_relax(s, false)
	s.step(2)
	assert_true(s.run.relax.illusions_allowed(), "out of the relax they may play")
