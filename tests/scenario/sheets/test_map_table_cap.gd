extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-14: at 20,000 strokes the pencil marks nothing until something is rubbed out (Gameplay
## §14.3, §A.11). The server drops a stroke or label past the cap and tells its drawer; the client,
## told the sheet is full, draws nothing at all. At the cap a rub that would split a stroke takes it
## whole instead, and once below the cap the pencil marks again.

const T = preload("res://tests/scenario/sheets/table_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_at_the_cap_the_pencil_marks_nothing_until_something_is_rubbed_out() -> void:
	var s: Scenario = T.camp(1601, self)
	var ann: MinerHandle = T.walk_up(s, "ann")
	var table: MapTable = s.run.sheets.table
	var cap: int = Tuning.i(&"mine.sheet_max_strokes")
	var others: int = table.author_index("someone")
	for i: int in cap - 1:
		var at: Vector2 = Vector2(-14000 + (i % 140) * 200, -14000 + floorf(i / 140.0) * 200)
		var dash: SheetStroke = SheetStroke.make(table.take_id(), others, PackedVector2Array([at, at + Vector2(20, 0)]))
		table.sheet.add_stroke(dash)
		table.keep_stroke(dash)
	assert_eq(table.sheet.count(), cap - 1)
	var long_line: PackedVector2Array = T.line(Vector2(0, 15000), Vector2(1200, 15000), 12)
	T.draw(ann, long_line)
	s.step(10)
	assert_eq(table.sheet.count(), cap, "the last one in")
	assert_true(ann.connection.sheet.full, "Ann's client is told the sheet is full")
	assert_eq(T.draw(ann, T.line(Vector2(0, 15500), Vector2(300, 15500), 3)), -1, "the pencil marks nothing")
	assert_eq(ann.connection.sheet.pending.size(), 0, "not even on Ann's own screen")
	assert_eq(ann.connection.sheet.commit_label(Vector2(0, 15800), "full", Transport.now_usec()), -1)
	# A modified client is held to it too.
	T.send_raw(ann, SheetCodec.commit_stroke(900, T.line(Vector2(0, 15500), Vector2(300, 15500), 3)))
	T.send_raw(ann, SheetCodec.commit_label(901, Vector2(0, 15800), "full"))
	s.step(3)
	assert_eq(T.refused_whys(s), ["full", "full"] as Array[String])
	assert_eq(table.sheet.count(), cap)
	# Rubbing through the long line's middle would make two pieces: at the cap it goes whole.
	ann.connection.sheet.rub(PackedVector2Array([Vector2(600, 15000)]))
	s.step(10)
	assert_eq(table.sheet.count(), cap - 1, "the line went whole, not in two")
	assert_false(ann.connection.sheet.full, "below the cap")
	var seq: int = T.draw(ann, T.line(Vector2(0, 15500), Vector2(300, 15500), 3))
	assert_gt(seq, 0, "the pencil marks again")
	s.step(10)
	assert_eq(table.sheet.count(), cap)
	assert_eq(ann.connection.sheet.pending.size(), 0, "accepted")
