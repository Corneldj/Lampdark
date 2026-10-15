extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-13: with no dark path to its target the Stythe goes to the reachable dark tile nearest it; it
## circles a light at 2.0 tiles/s on the dark edge round it, never in it.

const W = preload("res://tests/unit/creatures/stythe_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _room() -> FixtureMap:
	var rows: PackedStringArray = ["#".repeat(32)]
	for _y: int in 16:
		rows.append("#" + ".".repeat(30) + "#")
	rows.append("#".repeat(32))
	return FixtureMap.from_ascii(rows)


func test_nearest_dark_then_circling() -> void:
	var s: Scenario = make({"seed": 1261, "fixture": _room(), "overrides": W.ON})
	var st: StytheCreature = W.stythe(s, Vector2i(2, 2))
	var ann: MinerHandle = W.miner(s, "ann", Vector2i(16, 8))
	var lit: Array = []
	for y: int in range(5, 12):
		for x: int in range(13, 20):
			lit.append(Vector2i(x, y))
	s.run.light.grid.add_area("test", LbLightGrid.COLOUR_AMBER, 0, 0.5, lit)
	s.step(2)
	st.move.head_for(s.run, st, s.run.registry.get_entity(ann.entity_id).tile())
	var target: Vector2i = st.move.follower.heading_for
	assert_ne(target, Vector2i(16, 8), "no dark path to her")
	assert_true(st.unlit(s.run, target), "a dark tile")
	var d: float = Vector2(target).distance_to(Vector2(16, 8))
	assert_lte(d, 4.0 + 1e-6, "the reachable dark tile nearest her (the pool's edge)")
	for _i: int in 120:
		s.step(1)
	assert_lte(st.position(s.run).distance_to(Vector2(target) + Vector2(0.5, 0.5)), 0.01, "it went there")
	st.begin_circle(s.run, Vector2i(16, 8))
	var visited: Dictionary = {}
	var last: Vector2 = st.position(s.run)
	for _i: int in 300:
		s.step(1)
		var t: Vector2i = st.tile(s.run)
		assert_true(st.unlit(s.run, t), "never in the light, tick %d" % s.run.tick)
		assert_lte(st.position(s.run).distance_to(last), 2.0 / 20.0 + 1e-4, "at 2.0 tiles/s")
		last = st.position(s.run)
		visited[t] = true
	assert_eq(st.state.name, &"circle")
	assert_gte(visited.size(), 12, "pacing round the light")
