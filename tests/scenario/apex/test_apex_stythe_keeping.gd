extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-09 (Gameplay §3.6, §7.4): a Stythe keeping a body when the engine catches stays in its
## territory; once the body is carried out of its lair it leaves to lurk in the dark roads by the gates.

const A = preload("res://tests/scenario/apex/apex_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_it_keeps_then_leaves_once_the_body_is_carried_out() -> void:
	var s: Scenario = make({"seed": 9501, "fixture": A.E.T.C.scenario_fixture(),
		"overrides": A.ON.merged({"stythe.lurk_move_s": [1.0, 2.0]})})
	var gate: Gate = A.world(s, 160)
	var st: StytheCreature = A.stythe(s, A.on_road(gate, 110), A.on_road(gate, 140))
	s.step(1)
	var ann: MinerHandle = A.W.miner(s, "ann", A.on_road(gate, 107), 0.0)
	st.system.gate.pull_of = func(m: int) -> float: return 60.0 if m == ann.entity_id else 0.0
	assert_true(s.run_until(func(_sc: Scenario) -> bool: return st.state.name == &"keep", 2000), "it drags Ann home and keeps her")
	A.catch_now(s)
	var apex: ApexController = s.run.apex
	assert_true(apex.active)
	# While she lies unconscious in its row (before she comes round).
	for _i: int in 150:
		s.step(1)
		assert_true(st.keeps(), "it keeps her")
		assert_true(st.senses.in_territory(s.run, st, st.tile(s.run)), "home in its territory, the engine no matter")
	# Carried out: her body in base camp, beyond its senses.
	s.run.movement.place(s.run, ann.entity_id, Vector2(gate.middle() - gate.outward * 3) + Vector2(0.5, 0.5))
	assert_true(s.run_until(func(_sc: Scenario) -> bool: return not st.keeps(), 40), "nobody kept")
	assert_true(s.run_until(func(sc: Scenario) -> bool: return apex.region.has(st.tile(sc.run)), 1600),
		"it leaves to lurk in the roads by the gates")
