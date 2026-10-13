extends GutTest
## FND-09's ASCII fixtures: the legend, padding, cutting into cells, spots and gates.

const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_legend_and_spots() -> void:
	var f: FixtureMap = FixtureMap.from_ascii(PackedStringArray(["#####", "#a.C#", "#BTD#", "#G.b#", "###"]))
	assert_eq(f.cells.size(), 1)
	var tiles: Array = Variants.array(f.cells[0]["tiles"])
	assert_eq(str(tiles[1]).substr(0, 5), "#..c#", "spots are floor; C is coal")
	assert_eq(str(tiles[2]).substr(0, 5), "#BTD#", "brick, timber, air door")
	assert_eq(str(tiles[3]).substr(0, 5), "#S..#", "a gate is a shut steel gate")
	assert_eq(str(tiles[4]).substr(0, 5), "#####", "short rows are padded with rock")
	assert_eq(str(tiles[0]).length(), WorldIds.CELL_TILES)
	assert_eq(f.spot("a"), Vector2i(1, 1))
	assert_eq(f.spot("b"), Vector2i(3, 3))


func test_a_wide_picture_is_cut_into_cells() -> void:
	var row: String = "#".repeat(45)
	var f: FixtureMap = FixtureMap.from_ascii(PackedStringArray([row, "#" + ".".repeat(43) + "#", row]))
	assert_eq(f.cells.size(), 3, "45 tiles wide is three cells")
	var coords: Array = []
	for cell: Dictionary in f.cells:
		coords.append(cell["cell"])
	assert_eq(coords, [[0, 0], [1, 0], [2, 0]])
	var mine: Mine = Mine.new()
	assert_eq(f.load_into(mine), 3)
	assert_true(mine.native.is_walkable(Vector2i(30, 1)), "the corridor runs into the second cell")
	assert_false(mine.native.is_walkable(Vector2i(44, 1)))


func test_gates_are_numbered_groups() -> void:
	var f: FixtureMap = FixtureMap.from_ascii(PackedStringArray(["#G#", "#G#", "#.#", "GG#"]))
	assert_eq(f.gates.keys(), [1, 2], "two separate groups")
	var first: Array = f.gates[1]
	var tiles: PackedInt32Array = first[1]
	assert_eq(tiles, PackedInt32Array([1, 21]), "a vertical pair of tiles")


func test_spec_round_trip() -> void:
	var f: FixtureMap = FixtureMap.from_ascii(PackedStringArray(["#a.#"]), {"~": "~"})
	var back: FixtureMap = FixtureMap.from_spec(f.spec())
	assert_eq(back.cells, f.cells)
	assert_eq(FixtureMap.from_spec("named:test").map_name, "test")


func test_unknown_marks_are_reported() -> void:
	FixtureMap.from_ascii(PackedStringArray(["#?#"]))
	assert_push_error("unknown mark '?'")
