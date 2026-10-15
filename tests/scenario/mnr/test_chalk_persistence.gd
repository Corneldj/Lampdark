extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-10 with GEN-13: every mark is a diff-log record; its cell evicted and committed again, every
## mark returns exactly, floor and rib face alike.

const W = preload("res://tests/scenario/world/diff_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_marks_return_with_their_cell() -> void:
	var s: Scenario = make({"seed": 1031, "fixture": W.road()})
	W.miner(s, "ann", Vector2i(3, 1))
	s.step(2)
	var store: ChalkStore = s.run.chalk.store
	store.put(s.run, Vector2i(50, 1), ChalkMarks.Surface.FLOOR, ChalkMarks.glyph(ChalkMarks.Kind.ARROW, 4), 7)
	store.put(s.run, Vector2i(50, 1), ChalkMarks.Surface.NORTH, ChalkMarks.glyph(ChalkMarks.Kind.DIGIT_9), 7)
	store.put(s.run, Vector2i(55, 1), ChalkMarks.Surface.SOUTH, ChalkMarks.glyph(ChalkMarks.Kind.BANG), 7)
	store.put(s.run, Vector2i(10, 1), ChalkMarks.Surface.FLOOR, ChalkMarks.glyph(ChalkMarks.Kind.CROSS), 7)
	var want: Dictionary = store.marks.duplicate(true)
	var shown: Dictionary = s.run.vision.chalk.duplicate(true)
	assert_eq(s.run.diff_log.payload_of(W.FAR, DiffLog.Kind.CHALK, "50,1:n"), {"glyph": ChalkMarks.glyph(ChalkMarks.Kind.DIGIT_9)},
		"a record in its cell, at once")
	W.evict(s, W.FAR)
	for t: Variant in store.marks.keys():
		var tile: Vector2i = t
		if WorldCoords.cell_of(tile) == W.FAR:
			store.marks.erase(tile)
			s.run.vision.set_chalk(tile, PackedByteArray())
	W.restore(s, W.FAR)
	assert_eq(store.marks, want, "every mark back exactly, from the log")
	assert_eq(s.run.vision.chalk, shown, "and in the tile data again")
