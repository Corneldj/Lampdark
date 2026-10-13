extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-02, the dark walker: no planned tile at or above its threshold; a path is invalid the tick
## a tile on it lights; the Thin crosses 0.40; with no dark path, the reachable dark tile nearest
## the target.

const N = preload("res://tests/unit/creatures/nav_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_threshold() -> void:
	var s: Scenario = make({"seed": 3, "fixture": FixtureMap.from_ascii(N.road(20))})
	var nav: CreatureNav = s.run.creatures.nav
	s.run.light.grid.add_spot(0, Vector2i(10, 2), 0.40, 0)
	s.step(1)
	assert_false(Variants.flag(nav.native.path(NavModes.Mode.DARK, Vector2i(1, 2), Vector2i(20, 2), NavModes.dark())["found"]), "0.40 is a wall at 0.30")
	var thin: Dictionary = nav.native.path(NavModes.Mode.DARK, Vector2i(1, 2), Vector2i(20, 2), NavModes.dark(true))
	assert_true(Variants.flag(thin["found"]), "the Thin crosses 0.40")
	var nearest: Vector2i = nav.native.reachable_dark_tile_nearest(Vector2i(20, 2), Vector2i(1, 2), NavModes.dark())
	assert_eq(nearest, Vector2i(9, 2), "with no dark path: the reachable dark tile nearest the target")


func test_planned_dark_and_invalid_once_lit() -> void:
	var s: Scenario = make({"seed": 4, "fixture": FixtureMap.from_ascii(N.chambers())})
	var nav: CreatureNav = s.run.creatures.nav
	s.run.light.grid.add_spot(0, Vector2i(5, 6), 0.35, 0)
	s.run.light.grid.add_spot(0, Vector2i(6, 6), 0.29, 0)
	s.step(1)
	var plan: Dictionary = nav.native.path(NavModes.Mode.DARK, Vector2i(1, 6), Vector2i(30, 6), NavModes.dark())
	assert_true(Variants.flag(plan["found"]))
	var tiles: Array[Vector2i] = plan["tiles"]
	for t: Vector2i in tiles:
		assert_lt(s.run.light.light_at(t), Tuning.f(&"stythe.wall_level"), "planned tile %s is dark" % t)
	var mid: Vector2i = tiles[tiles.size() / 2]
	assert_true(nav.native.still_valid(NavModes.Mode.DARK, tiles, NavModes.dark()))
	s.run.light.grid.add_spot(0, mid, 0.5, 0)
	s.step(1)
	assert_false(nav.native.still_valid(NavModes.Mode.DARK, tiles, NavModes.dark()), "a tile lit: the path is invalid that tick")
