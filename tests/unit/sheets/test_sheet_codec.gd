extends GutTest
## LFT-14: the sheets' wire form (SheetCodec) round-trips every op, takes a message whole or not at
## all, and a worst-case sheet, 20,000 strokes of the most points or 20,000 labels of the most
## bytes, serialises within the map table's 4 MB (GDD §15.9) in the diff log's section.


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_every_op_round_trips() -> void:
	var pts: PackedVector2Array = PackedVector2Array([Vector2(-3, 4), Vector2(100, 4), Vector2(100, -120)])
	var msg: PackedByteArray = PackedByteArray()
	msg.append_array(SheetCodec.commit_stroke(65535, pts))
	msg.append_array(SheetCodec.commit_label(7, Vector2(-16384, 16383), "Here be the Stythe"))
	msg.append_array(SheetCodec.rub(pts))
	msg.append_array(SheetCodec.sketch(9, pts))
	msg.append_array(SheetCodec.resync())
	msg.append_array(SheetCodec.reset())
	msg.append_array(SheetCodec.add_stroke(4000000000, pts))
	msg.append_array(SheetCodec.add_label(12, Vector2(3, -9), "pump", "76561198000000001"))
	msg.append_array(SheetCodec.remove(13))
	msg.append_array(SheetCodec.accept(5, 14))
	msg.append_array(SheetCodec.dropped(6))
	msg.append_array(SheetCodec.full(true))
	msg.append_array(SheetCodec.pen(65535, pts))
	msg.append_array(SheetCodec.pen_up(2))
	msg.append_array(SheetCodec.freeze(-1234567890123, 19999, "run-uuid"))
	var ops: Array[Dictionary] = SheetCodec.decode(msg)
	assert_eq(ops.size(), 15)
	# Ops with points also carry their blob as sent (the server keeps and forwards those bytes).
	for d: Dictionary in ops:
		if d.has("points"):
			var blob: PackedByteArray = d["blob"]
			var pts_in: PackedVector2Array = d["points"]
			assert_eq(blob, SheetStroke.encode(pts_in), "the blob is the points' own")
			d.erase("blob")
	assert_eq(ops[0], {"op": SheetCodec.Op.COMMIT_STROKE, "seq": 65535, "points": pts})
	assert_eq(ops[1], {"op": SheetCodec.Op.COMMIT_LABEL, "seq": 7, "anchor": Vector2(-16384, 16383), "text": "Here be the Stythe"})
	assert_eq(ops[2], {"op": SheetCodec.Op.RUB, "points": pts})
	assert_eq(ops[3], {"op": SheetCodec.Op.SKETCH, "seq": 9, "points": pts})
	assert_eq(int(Variants.number(ops[4]["op"])), SheetCodec.Op.RESYNC)
	assert_eq(int(Variants.number(ops[5]["op"])), SheetCodec.Op.RESET)
	assert_eq(ops[6], {"op": SheetCodec.Op.ADD_STROKE, "id": 4000000000, "points": pts})
	assert_eq(ops[7], {"op": SheetCodec.Op.ADD_LABEL, "id": 12, "anchor": Vector2(3, -9), "text": "pump", "author": "76561198000000001"})
	assert_eq(ops[8], {"op": SheetCodec.Op.REMOVE, "id": 13})
	assert_eq(ops[9], {"op": SheetCodec.Op.ACCEPT, "seq": 5, "id": 14})
	assert_eq(ops[10], {"op": SheetCodec.Op.DROPPED, "seq": 6})
	assert_eq(ops[11], {"op": SheetCodec.Op.FULL, "on": true})
	assert_eq(ops[12], {"op": SheetCodec.Op.PEN, "pen": 65535, "points": pts})
	assert_eq(ops[13], {"op": SheetCodec.Op.PEN_UP, "pen": 2})
	assert_eq(ops[14], {"op": SheetCodec.Op.FREEZE, "digest": -1234567890123, "count": 19999, "run_uuid": "run-uuid"})


func test_a_message_is_taken_whole_or_not_at_all() -> void:
	var msg: PackedByteArray = SheetCodec.remove(1)
	msg.append_array(SheetCodec.add_stroke(2, PackedVector2Array([Vector2(0, 0), Vector2(20, 0)])))
	for cut: int in range(1, msg.size()):
		if cut == SheetCodec.remove(1).size():
			continue
		assert_eq(SheetCodec.decode(msg.slice(0, cut)).size(), 0, "cut at %d" % cut)
	assert_eq(SheetCodec.decode(PackedByteArray([99])).size(), 0, "an unknown op")
	assert_eq(SheetCodec.decode(PackedByteArray([SheetCodec.Op.FULL, 2])).size(), 0, "a flag is 0 or 1")
	assert_true(SheetCodec.commit_stroke(1, PackedVector2Array()).is_empty(), "no points, nothing to send")


## The worst case at the cap, in the diff log's run-level section as MapTable keeps it.
func _section_bytes(fill: Callable) -> Dictionary:
	var run: RunState = RunState.create(1, ServerConfig.Mode.FRIENDS, false)
	run.diff_log = DiffLog.new()
	var table: MapTable = MapTable.new()
	table.bind(run)
	for i: int in 4:
		table.author_index("7656119800000000%d" % i)
	fill.call(table)
	var bytes: int = run.diff_log.sizes()["map_table"]
	var whole: int = run.diff_log.store.serialise().size()
	return {"section": bytes, "whole": whole, "count": table.sheet.count()}


func test_a_worst_case_sheet_serialises_within_4_mb() -> void:
	var cap: int = Tuning.i(&"mine.sheet_max_strokes")
	var points: int = Tuning.i(&"mine.sheet_stroke_max_points")
	var budget: int = Tuning.i(&"mine.map_table_save_budget_mb") * 1024 * 1024
	var strokes: Callable = func(table: MapTable) -> void:
		var pts: PackedVector2Array = PackedVector2Array()
		for p: int in points:
			pts.append(Vector2(-16000 + (p % 2) * 127, -16000 + p * 127))
		for i: int in cap:
			var s: SheetStroke = SheetStroke.make(table.take_id(), i % 4, pts)
			table.sheet.add_stroke(s)
			table.keep_stroke(s)
	var s1: Dictionary = _section_bytes(strokes)
	gut.p("20,000 strokes of %d points: %d bytes in the section, %d serialised" % [points, s1["section"], s1["whole"]])
	assert_eq(int(Variants.number(s1["count"])), cap)
	assert_lte(int(Variants.number(s1["whole"])), budget, "strokes at the cap within 4 MB")
	var labels: Callable = func(table: MapTable) -> void:
		# 40 characters of four UTF-8 bytes each: the most a label may weigh.
		var text: String = "𐌰".repeat(Tuning.i(&"mine.sheet_label_max_chars"))
		for i: int in cap:
			var l: SheetLabel = SheetLabel.make(table.take_id(), i % 4, Vector2(i % 1000, floorf(i / 1000.0)), text)
			table.sheet.add_label(l)
			table.keep_label(l)
	var s2: Dictionary = _section_bytes(labels)
	gut.p("20,000 labels of 160 bytes: %d bytes in the section, %d serialised" % [s2["section"], s2["whole"]])
	assert_lte(int(Variants.number(s2["whole"])), budget, "labels at the cap within 4 MB")


func test_the_table_rebuilds_from_its_section() -> void:
	var run: RunState = RunState.create(1, ServerConfig.Mode.FRIENDS, false)
	run.diff_log = DiffLog.new()
	var table: MapTable = MapTable.new()
	table.bind(run)
	var ann: int = table.author_index("ann")
	var bob: int = table.author_index("bob")
	var s: SheetStroke = SheetStroke.make(table.take_id(), ann, PackedVector2Array([Vector2(1, 2), Vector2(30, 2)]))
	table.sheet.add_stroke(s)
	table.keep_stroke(s)
	var l: SheetLabel = SheetLabel.make(table.take_id(), bob, Vector2(-40, 9), "chalk 4, by the wall")
	table.sheet.add_label(l)
	table.keep_label(l)
	var gone: SheetStroke = SheetStroke.make(table.take_id(), bob, PackedVector2Array([Vector2(0, 0)]))
	table.sheet.add_stroke(gone)
	table.keep_stroke(gone)
	table.sheet.remove(gone.id)
	table.forget(gone.id)
	var restored: RunState = RunState.create(1, ServerConfig.Mode.FRIENDS, false)
	restored.diff_log = DiffLog.new()
	assert_true(restored.diff_log.deserialise(run.diff_log.serialise(run)), "a save brings the table up to date first")
	var back: MapTable = MapTable.new()
	back.bind(restored)
	back.load_from_section()
	assert_eq(back.sheet.count(), 2)
	assert_eq(back.sheet.digest(), table.sheet.digest(), "the same strokes and labels")
	assert_eq(back.authors, PackedStringArray(["ann", "bob"]))
	var again: SheetLabel = back.sheet.labels[l.id]
	assert_eq(again.author, bob, "authors kept for the public rubber and blocks")
	assert_gt(back.next_id, gone.id, "ids are never reused")
