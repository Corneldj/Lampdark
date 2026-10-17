extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-09 (Gameplay §3.6, §10.8): the cap binds through the apex. A lone miner on the road with all
## three creatures awake to the engine faces two hunters at most: at crew count 1 the cap is 2, a
## third commit is refused even in the apex, and at no tick are more than 2 active.

const A = preload("res://tests/scenario/apex/apex_world.gd")
const M = preload("res://tests/scenario/creatures/moth_awake_world.gd")
const T = preload("res://tests/scenario/creatures/hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_lone_miner_faces_two_hunters_at_most() -> void:
	var s: Scenario = make({"seed": 9301, "fixture": A.E.T.C.scenario_fixture(), "overrides": A.ON})
	var gate: Gate = A.world(s, 120)
	var m: Moth = A.moth(s, A.on_road(gate, 60))
	var t: Tapper = A.tapper(s, A.in_rock(gate, 30, 5))
	var st: StytheCreature = A.stythe(s, A.on_road(gate, 100), A.on_road(gate, 104))
	var ann: MinerHandle = M.lit_miner(s, "ann", A.on_road(gate, 30))
	s.step(3)
	var hunts: HuntGate = s.run.creatures.gate
	assert_eq(int(Variants.number(hunts.crew_count.call())), 1, "crew count 1")
	assert_eq(int(Variants.number(hunts.cap_for.call(1))), 2, "the cap: 2")
	A.catch_now(s)
	# Two take the places; the third is refused, apex or not.
	assert_true(hunts.request_commit(s.run, m, ann.entity_id, true))
	assert_true(hunts.request_commit(s.run, t, ann.entity_id, true))
	assert_false(hunts.request_commit(s.run, st, ann.entity_id, true), "a third commit refused in the apex")
	var most: int = 0
	for i: int in 600:
		s.step(1)
		if i % 40 == 0:
			T.talk(s, ann)
		most = maxi(most, hunts.active_count())
		assert_lte(hunts.active_count(), 2, "never more than 2 active (tick %d)" % s.run.tick)
	assert_gt(most, 0)
