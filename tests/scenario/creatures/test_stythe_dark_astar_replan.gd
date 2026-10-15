extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-13: moving, the Stythe's dark path is replanned within every 5 ticks (4 Hz), and the same tick
## a tile on it lights.

const W = preload("res://tests/unit/creatures/stythe_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_replans_at_4_hz_and_when_a_tile_lights() -> void:
	var s: Scenario = make({"seed": 1251, "fixture": W.road(80), "overrides": W.ON})
	var st: StytheCreature = W.stythe(s, Vector2i(2, 2))
	s.step(1)
	st.move.head_for(s.run, st, Vector2i(75, 2))
	var plans: Array[int] = []
	var last: int = st.move.follower.replans
	for _i: int in 60:
		s.step(1)
		if st.move.follower.replans != last:
			plans.append(s.run.tick)
			last = st.move.follower.replans
	for i: int in range(1, plans.size()):
		assert_lte(plans[i] - plans[i - 1], 5, "replanned within 5 ticks")
	assert_gte(plans.size(), 11)
	var ahead: Vector2i = st.tile(s.run) + Vector2i(4, 0)
	var before: int = st.move.follower.replans
	W.light(s, ahead, 0.5)
	s.step(1)
	assert_gt(st.move.follower.replans, before, "the same tick a path tile lit")
