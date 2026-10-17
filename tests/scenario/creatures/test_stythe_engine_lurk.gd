extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-14 with an LFT-09 stub: while the engine runs the Stythe lurks within 40 tiles of the gates,
## unless it keeps a body (then it stays in its territory).

const H = preload("res://tests/scenario/creatures/stythe_hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_lurks_near_the_gates_unless_it_keeps() -> void:
	# Bob lies in the lair for the whole test: alone, his self-revive (RSC-09) would bring him round
	# and a second fall would wipe the run (LFT-11), whose Lamp Check freezes the mine.
	var s: Scenario = make({"seed": 1481, "fixture": H.road(150),
		"overrides": H.W.ON.merged({"stythe.lurk_move_s": [1.0, 2.0], "rescue.self_revive_delay_s": 600.0})})
	var st: StytheCreature = H.W.stythe(s, Vector2i(140, 2), Vector2i(140, 2))
	var gates: Vector2 = Vector2(5.5, 2.5)
	st.apex_point = func() -> Variant: return gates
	s.step(400)
	var near: float = st.position(s.run).distance_to(gates)
	gut.p("from the gates: %.1f tiles" % near)
	for _i: int in 600:
		s.step(1)
		assert_lte(st.position(s.run).distance_to(gates), maxf(near, 40.0) + 1e-3, "it stays by the gates")
	assert_lte(st.position(s.run).distance_to(gates), 40.0 + 1e-3, "within 40 tiles")
	# A body laid in its lair (CRT-15): it keeps while the body lies there.
	var bob: MinerHandle = H.W.miner(s, "bob", Vector2i(139, 2))
	s.step(1)  # DIR-05's census counts him first: the run's one human, alone, his self-revive waits
	assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.MOTH_SMOTHER))
	assert_true(s.run_until(func(sc: Scenario) -> bool: return sc.run.falls.bodies.has(bob.entity_id), 40))
	st.home.lay(s.run, st, bob.entity_id, 0)
	st.kept.append(bob.entity_id)
	st.enter(s.run, &"keep", "test")
	s.step(1200)
	assert_eq(st.kept, [bob.entity_id] as Array[int], "still keeping")
	assert_true(st.senses.in_territory(s.run, st, st.tile(s.run)), "keeping a body: back in its territory")
