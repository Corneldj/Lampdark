extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-03 (§6.6): a POINT (a spot lit to 0.30 for 2 s) held on the sleeping Moth starts a stir,
## which then settles: alone it never wakes it.

const W = preload("res://tests/scenario/creatures/moth_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_point() -> void:
	var s: Scenario = make({"seed": 15, "fixture": W.road()})
	var m: Moth = W.moth(s)
	s.step(2)
	s.run.light.grid.add_spot(0, W.ROOST, 0.30, 40)
	var states: Array[StringName] = []
	s.on_tick = func(_sc: Scenario) -> void:
		if states.is_empty() or states[states.size() - 1] != m.state.name:
			states.append(m.state.name)
	s.step(200)
	assert_eq(states, [&"asleep", &"stirring", &"settling", &"asleep"] as Array[StringName], "it stirs once, then settles")
