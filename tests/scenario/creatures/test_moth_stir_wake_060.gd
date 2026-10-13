extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-03: 0.60 at any moment starts a stir that always wakes it, even if the light is gone by
## the stir's end.

const W = preload("res://tests/scenario/creatures/moth_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_060() -> void:
	var s: Scenario = make({"seed": 13, "fixture": W.road()})
	var m: Moth = W.moth(s)
	s.step(2)
	W.light_on(s, 0.60, 1)
	assert_lte(W.until_not(s, m, &"asleep"), 2, "a single tick of 0.60 stirs it")
	assert_eq(W.until_not(s, m, &"stirring"), 30)
	assert_eq(m.state.name, &"frenzy", "and it always wakes")
	assert_eq(str(m.waker["cause"]), "bright")
