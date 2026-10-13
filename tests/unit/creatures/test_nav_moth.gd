extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-02, the walker: closed air doors pass (the hold is the follower's), shut gates never;
## prowling hugs the ribs; hunting is a shortest path.

const N = preload("res://tests/unit/creatures/nav_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_doors_and_gates() -> void:
	var rows: PackedStringArray = N.road(20)
	rows[2] = "#.....D.....G........#"
	var s: Scenario = make({"seed": 1, "fixture": FixtureMap.from_ascii(rows)})
	var nav: CreatureNav = s.run.creatures.nav
	assert_true(Variants.flag(nav.native.path(NavModes.Mode.WALKER, Vector2i(1, 2), Vector2i(10, 2))["found"]), "through the closed air door")
	assert_false(Variants.flag(nav.native.path(NavModes.Mode.WALKER, Vector2i(1, 2), Vector2i(15, 2))["found"]), "never through a shut gate")
	assert_true(s.set_gate(2, true), "open the gate")
	assert_true(Variants.flag(nav.native.path(NavModes.Mode.WALKER, Vector2i(1, 2), Vector2i(15, 2))["found"]), "an open gate is floor")


func test_prowl_hugs_the_ribs_and_hunting_is_shortest() -> void:
	var s: Scenario = make({"seed": 2, "fixture": FixtureMap.from_ascii(N.chambers())})
	var nav: CreatureNav = s.run.creatures.nav
	var from: Vector2i = Vector2i(1, 3)
	var to: Vector2i = Vector2i(32, 11)
	var crawl: Dictionary = nav.native.path(NavModes.Mode.CRAWLER, from, to)
	assert_true(Variants.flag(crawl["found"]))
	var tiles: Array[Vector2i] = crawl["tiles"]
	var edge: int = 0
	for t: Vector2i in tiles:
		if nav.native.wall_adjacent(t):
			edge += 1
	var ratio: float = float(edge) / tiles.size()
	gut.p("prowl: %d of %d path tiles wall-adjacent (%.0f%%)" % [edge, tiles.size(), ratio * 100.0])
	assert_gte(ratio, 0.8)
	var hunt: Dictionary = nav.native.path(NavModes.Mode.WALKER, from, to)
	var shortest: Mine.PathAnswer = s.run.mine.path_distance(from, to, 200.0)
	assert_almost_eq(Variants.number(hunt["cost"]), shortest.distance, 0.001, "hunting takes the shortest path")
