extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-10: a roof fall (HAZ-03's stub call) erases the marks on its fallen tiles, and on the rib
## faces bordering them, and nothing else; the diff log forgets them too.

const C = preload("res://tests/unit/mnr/chalk_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_fall_erases_only_its_tiles() -> void:
	var s: Scenario = make({"seed": 1041, "fixture": C.B.room()})
	C.miner(s, "ann", Vector2i(2, 3))
	s.step(2)
	var store: ChalkStore = s.run.chalk.store
	var g: int = ChalkMarks.glyph(ChalkMarks.Kind.CROSS)
	for x: int in range(5, 10):
		store.put(s.run, Vector2i(x, 3), ChalkMarks.Surface.FLOOR, g, 1)
	store.put(s.run, Vector2i(7, 2), ChalkMarks.Surface.SOUTH, g, 1)  # a face onto (7, 3)
	store.put(s.run, Vector2i(7, 2), ChalkMarks.Surface.FLOOR, g, 1)  # its floor, not fallen
	var erased: int = store.erase_chalk(s.run, [Vector2i(6, 3), Vector2i(7, 3)] as Array[Vector2i])
	assert_eq(erased, 3, "two floors and the face onto a fallen tile")
	assert_eq(store.glyph_at(Vector2i(6, 3), ChalkMarks.Surface.FLOOR), 0)
	assert_eq(store.glyph_at(Vector2i(7, 3), ChalkMarks.Surface.FLOOR), 0)
	assert_eq(store.glyph_at(Vector2i(7, 2), ChalkMarks.Surface.SOUTH), 0, "a face that bordered the fall")
	assert_ne(store.glyph_at(Vector2i(7, 2), ChalkMarks.Surface.FLOOR), 0, "the floor beside it stays")
	assert_ne(store.glyph_at(Vector2i(5, 3), ChalkMarks.Surface.FLOOR), 0)
	assert_ne(store.glyph_at(Vector2i(8, 3), ChalkMarks.Surface.FLOOR), 0)
	assert_true(s.run.diff_log.payload_of(Vector2i.ZERO, DiffLog.Kind.CHALK, "6,3:f").is_empty(), "gone from the log")
	assert_false(s.run.vision.chalk.has(Vector2i(6, 3)), "and from the tile data")
