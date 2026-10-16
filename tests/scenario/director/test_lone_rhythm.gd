extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-03 (Gameplay §10.9): the lone rhythm after an ebb. A lone miner whose hunt ends at Pull 50
## (the ebb takes them to 20) is marked again in 3 min 20 s on the Second Level (+9 a minute) and
## 2 min 30 s on the Third (+12).

const D = preload("res://tests/scenario/director/draught_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _regain(ring: int, seed_value: int) -> float:
	var s: Scenario = make({"seed": seed_value, "fixture": D.hall(), "director": true})
	var ids: Array[int] = D.crew(s, ["ann", "ben"] as Array[String], ["a", "f"] as Array[String])
	D.stand_in(s)
	s.run.pull.ring_of = func(_m: int) -> int: return ring
	s.step(2)
	s.run.pull.set_value(ids[0], 50.0)
	s.run.creatures.gate.hunt_ended.emit(null, ids[0], "it lost her")
	assert_almost_eq(s.run.pull.value_of(ids[0]), 20.0, 1e-6, "the ebb: 50 to 20")
	var ticks: int = 0
	while s.run.pull.value_of(ids[0]) < 50.0 - 1e-9 and ticks < 20000:
		s.step(1)
		ticks += 1
	return ticks / Tuning.f(&"net.tick_hz")


func test_marked_again_in_3_20_on_the_second_level_and_2_30_on_the_third() -> void:
	assert_almost_eq(_regain(2, 2501), 200.0, 0.5, "3 min 20 s on the Second Level")
	assert_almost_eq(_regain(3, 2502), 150.0, 0.5, "2 min 30 s on the Third")
