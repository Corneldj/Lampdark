extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-14: in a relax Lurk never turns to Hunt, but a miner who walks unlit within 1.5 tiles is still
## grabbed. (DIR-02: in a relax it drifts home to its lair, so Ann meets it there.)

const H = preload("res://tests/scenario/creatures/stythe_hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_no_hunt_in_a_relax_but_a_walk_in_is_taken() -> void:
	var s: Scenario = make({"seed": 1471, "fixture": H.road(), "overrides": H.W.ON})
	var h: H = H.new()
	h.build(s, 40, 30, 95)
	s.run.creatures.gate.relax_active = func() -> bool: return true
	for _i: int in 1600:
		s.step(1)
		assert_ne(h.st.state.name, &"hunt", "no chosen hunt in a relax")
		if h.st.at_home(s.run, h.st.tile(s.run)):
			break
	assert_true(h.st.at_home(s.run, h.st.tile(s.run)), "it drifted home to its lair (DIR-02)")
	var at: Vector2 = h.st.position(s.run)
	s.run.movement.place(s.run, h.ann.entity_id, at - Vector2(4.0, 0.0))
	s.step(2)
	assert_ne(h.st.state.name, &"hunt", "4 tiles off, she is no walk-in: still no hunt")
	h.ann.at(s.run.tick + 1).move(0.0, InputRecord.Gait.WALK, 200)
	assert_true(s.run_until(func(_sv: Variant) -> bool: return s.run.miner_state.life(h.ann.entity_id) == MinerTransitions.Life.GRABBED, 300),
		"she walked into its reach and was taken")
