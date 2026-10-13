extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-04: at an unheld lamp, everyone in its core when the wind-up ends falls, and the lamp goes
## out (M1: it stays where it lay, snuffed, until CRT-05 takes lamps home). Anyone outside the
## core stays up.

const A = preload("res://tests/scenario/creatures/moth_awake_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_core() -> void:
	var s: Scenario = make({"seed": 80, "fixture": A.hall(40, 20)})
	var m: Moth = A.awake(s, Vector2i(5, 10), false)
	var lamp: GauzeLamp = s.run.lamps.create(s.run, 1.0, 3, true, LampRules.WICK_UP, Vector2(20.5, 10.5))
	var bob: MinerHandle = s.add_miner("bob", Vector2i(21, 10))
	var cy: MinerHandle = s.add_miner("cy", Vector2i(18, 11))
	var dee: MinerHandle = s.add_miner("dee", Vector2i(25, 10))
	s.step(1)
	assert_eq(lamp.state(), GauzeLamp.State.SET_DOWN_OPEN)
	assert_gte(A.until_state(s, m, &"linger", 600), 0, "it reached the lamp and smothered")
	var record: Dictionary = s.run.creatures.log.of_type(&"moth_smother")[0]
	assert_eq(str(record["kind"]), "unheld")
	assert_eq(A.life(s, bob.entity_id), MinerTransitions.Life.UNCONSCIOUS, "bob, 1 tile from it, in the 3.3-tile core")
	assert_eq(A.life(s, cy.entity_id), MinerTransitions.Life.UNCONSCIOUS, "cy, 2.5 tiles off, too")
	assert_eq(A.life(s, dee.entity_id), MinerTransitions.Life.UPRIGHT, "dee, 4.5 tiles off, outside the core")
	assert_eq(lamp.state(), GauzeLamp.State.OUT, "the lamp goes out")
