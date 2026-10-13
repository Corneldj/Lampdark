extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-02, the rock mover and reach: never brick, nothing in a brick-lined zone on its path; reach
## fixtures (a 3-wide road's middle in reach, a 5-wide chamber's not, brick and timber never).


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_never_brick() -> void:
	var rows: PackedStringArray = PackedStringArray([
		"##############################",
		"##############################",
		"#............................#",
		"##############BBBBBBBBBBBBBBBB",
		"##############B.............B#",
		"##############B.............B#",
		"##############BBBBBBBBBBBBBBB#",
		"##############################",
		"##############################",
	])
	var s: Scenario = make({"seed": 5, "fixture": FixtureMap.from_ascii(rows)})
	var nav: CreatureNav = s.run.creatures.nav
	var across: Dictionary = nav.native.path(NavModes.Mode.ROCK, Vector2i(3, 0), Vector2i(3, 6))
	assert_true(Variants.flag(across["found"]), "beneath the road")
	var into: Dictionary = nav.native.path(NavModes.Mode.ROCK, Vector2i(3, 0), Vector2i(20, 4))
	assert_false(Variants.flag(into["found"]), "the brick-lined room is beyond it")
	var along: Dictionary = nav.native.path(NavModes.Mode.ROCK, Vector2i(3, 8), Vector2i(28, 8))
	assert_true(Variants.flag(along["found"]))
	var tiles: Array[Vector2i] = along["tiles"]
	for t: Vector2i in tiles:
		assert_ne(s.run.mine.native.effective_material(t), WorldIds.TileMaterial.BRICK, "never a brick tile")
		assert_false(t.y >= 4 and t.y <= 5 and t.x >= 15 and t.x <= 27, "never in the brick-lined room")


func test_reach() -> void:
	var rows: PackedStringArray = PackedStringArray([
		"####################",
		"#..................#",
		"#..................#",
		"#..................#",
		"####################",
		"####################",
		"#..................#",
		"#..................#",
		"#..................#",
		"#..................#",
		"#..................#",
		"####################",
		"BBBBBBBBBBBBBBBBBBBB",
		"B..................B",
		"B..................B",
		"B..................B",
		"TTTTTTTTTTTTTTTTTTTT",
	])
	var s: Scenario = make({"seed": 6, "fixture": FixtureMap.from_ascii(rows)})
	var nav: CreatureNav = s.run.creatures.nav
	assert_true(nav.in_tapper_reach(Vector2(9.5, 2.5)), "the middle of a 3-wide road")
	assert_false(nav.in_tapper_reach(Vector2(9.5, 8.5)), "the middle of a 5-wide chamber")
	assert_true(nav.in_tapper_reach(Vector2(9.5, 7.5)), "off the chamber's centre line")
	assert_false(nav.in_tapper_reach(Vector2(9.5, 14.5)), "brick and timber faces are never returned")
	for t: Vector2i in nav.native.usable_faces_within(Vector2(9.5, 13.5), 2.0):
		var m: int = s.run.mine.native.effective_material(t)
		assert_true(m == WorldIds.TileMaterial.ROCK or m == WorldIds.TileMaterial.COAL)
	var behind: Vector2i = nav.native.rock_tile_behind(Vector2i(9, 1))
	assert_eq(behind, Vector2i(9, 0))
	var face: Vector2i = nav.native.nearest_usable_face(Vector2(9.5, 8.6), 4)
	assert_eq(face, Vector2i(9, 11))
