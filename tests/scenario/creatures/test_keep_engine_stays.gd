extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-15 with an LFT-09 stub: while the engine runs, a Stythe that keeps a body stays home in its
## territory, never drawn to lurk by the gates.

const H = preload("res://tests/scenario/creatures/stythe_hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_keeping_stythe_stays_home_at_the_engine() -> void:
	var s: Scenario = make({"seed": 1521, "fixture": H.road(150), "overrides": H.W.ON.merged({"stythe.lurk_move_s": [1.0, 2.0]})})
	var h: H = H.new()
	h.build(s, 110, 107, 145)
	assert_true(h.until_state(&"keep", 1600), "it keeps Ann")
	var gates: Vector2 = Vector2(5.5, 2.5)
	h.st.apex_point = func() -> Variant: return gates
	for _i: int in 1200:
		s.step(1)
		assert_true(h.st.senses.in_territory(s.run, h.st, h.st.tile(s.run)), "home, in its territory")
		assert_gt(h.st.position(s.run).distance_to(gates), Tuning.f(&"stythe.apex_lurk_gate_tiles"), "never by the gates")
	assert_true(h.st.keeps())
