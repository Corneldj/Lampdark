extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-03: light at 0.30 for 1.0 s in all within 10 s stirs it; gone by the stir's end, it
## settles (60 ticks), sleeps again and never frenzies. Still on it at the end, it wakes.

const W = preload("res://tests/scenario/creatures/moth_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_settles_without_light() -> void:
	var s: Scenario = make({"seed": 11, "fixture": W.road()})
	var m: Moth = W.moth(s)
	W.light_on(s, 0.31, 10)
	s.step(100)
	assert_eq(m.state.name, &"asleep", "one half-second look: nothing")
	W.light_on(s, 0.31, 10)
	var states: Dictionary = {}
	s.on_tick = func(_sc: Scenario) -> void: states[m.state.name] = true
	s.step(150)
	assert_true(states.has(&"stirring"), "the second look within 10 s stirs it")
	assert_true(states.has(&"settling"))
	assert_false(states.has(&"frenzy"), "no frenzy")
	assert_eq(m.state.name, &"asleep")
	var logged: Array[Dictionary] = s.run.creatures.log.of_type(&"moth_stir")
	assert_eq(logged.size(), 1)
	assert_eq(str(logged[0]["cause"]), "clock")


func test_wakes_with_light_still_on() -> void:
	var s: Scenario = make({"seed": 12, "fixture": W.road()})
	var m: Moth = W.moth(s)
	W.light_on(s, 0.40)
	W.until_not(s, m, &"asleep")
	W.until_not(s, m, &"stirring")
	assert_eq(m.state.name, &"frenzy", "0.30 or more at the end: it wakes")
	assert_eq(str(m.waker["cause"]), "clock")
	assert_eq(int(Variants.number(m.waker["until"])) - s.run.tick, 199, "the waker known for 10 s")
