extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-13 with DIR-06's staged run 1: the Stythe never leaves its territory, lurking or chasing.

const W = preload("res://tests/unit/creatures/stythe_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_never_leaves_its_territory() -> void:
	var s: Scenario = make({"seed": 1291, "fixture": W.road(150), "overrides": W.ON.merged({"stythe.lurk_move_s": [1.0, 2.0]})})
	var st: StytheCreature = W.stythe(s, Vector2i(20, 2), Vector2i(20, 2))
	st.staged = func() -> bool: return true
	var ann: MinerHandle = W.miner(s, "ann", Vector2i(140, 2))
	s.step(2)
	var furthest: float = 0.0
	var hunted: bool = false
	for i: int in 1600:
		if i == 800:
			W.pull(st, {ann.entity_id: 80.0})  # eligible anywhere: it hunts her, but staged it stays home
		s.step(1)
		hunted = hunted or st.hunt.target == ann.entity_id
		furthest = maxf(furthest, st.senses.lair_distance(s.run, st, st.tile(s.run)))
	assert_true(hunted, "it hunted her")
	gut.p("furthest from the lair: %.1f tiles" % furthest)
	assert_lte(furthest, Tuning.f(&"stythe.territory_tiles") + 1e-6, "inside its territory throughout")
	assert_gt(furthest, 5.0, "it did move")
