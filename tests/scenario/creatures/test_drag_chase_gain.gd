extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-14: a drag moves at 2.0 tiles/s, so a walking rescuer gains 1 tile a second on it and a runner
## 3.5 (MNR-01's 3.0 and 5.5).

const H = preload("res://tests/scenario/creatures/stythe_hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_walker_and_runner_gain() -> void:
	assert_almost_eq(Tuning.f(&"movement.walk_speed") - Tuning.f(&"stythe.drag_speed"), 1.0, 1e-6, "a walker gains 1 tile/s")
	assert_almost_eq(Tuning.f(&"movement.run_speed") - Tuning.f(&"stythe.drag_speed"), 3.5, 1e-6, "a runner 3.5")
	var s: Scenario = make({"seed": 1491, "fixture": H.road(), "overrides": H.W.ON})
	var h: H = H.new()
	h.build(s, 40, 37, 95)
	var bob: MinerHandle = H.W.miner(s, "bob", Vector2i(20, 2), 0.0)
	assert_true(h.until_state(&"drag", 300))
	var gap0: float = h.st.position(s.run).x - s.run.registry.get_entity(bob.entity_id).position.x
	bob.at(s.run.tick + 1).move(0.0, InputRecord.Gait.WALK, 60)
	s.step(42)
	var gap1: float = h.st.position(s.run).x - s.run.registry.get_entity(bob.entity_id).position.x
	gut.p("gap %.2f -> %.2f in 2 s" % [gap0, gap1])
	assert_almost_eq(gap0 - gap1, 2.0, 0.3, "about 1 tile a second walking")
