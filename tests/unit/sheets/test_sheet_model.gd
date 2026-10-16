extends GutTest
## LFT-14: the sheet model (Gameplay §12.7, §A.11). Strokes and labels with ids, a label counting as
## one stroke; the rubber (Proposed: partial) cutting a stroke where it crosses its edge, so one
## stroke may become pieces that each count, and taking a label whole; past the cap the whole
## stroke goes instead; nothing ever snaps.


func before_all() -> void:
	assert_true(Tuning.load_server())


func _line(from: Vector2, to: Vector2, steps: int) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in steps + 1:
		out.append(from.lerp(to, float(i) / steps).round())
	return out


func _ids() -> Callable:
	var next: Array[int] = [100]
	return func() -> int:
		next[0] += 1
		return next[0]


func test_a_stroke_round_trips_as_int16_start_and_int8_deltas() -> void:
	var pts: PackedVector2Array = PackedVector2Array([Vector2(-16384, 16383), Vector2(-16257, 16256), Vector2(-16384, 16383)])
	var blob: PackedByteArray = SheetStroke.encode(pts)
	assert_eq(blob.size(), SheetStroke.blob_size(3), "a count byte, 4 for the start, 2 a step")
	var back: Array = SheetStroke.decode(blob)
	var got: PackedVector2Array = back[0]
	assert_eq(got, pts)
	assert_eq(int(Variants.number(back[1])), blob.size())
	assert_true(SheetStroke.encode(PackedVector2Array([Vector2(0, 0), Vector2(128, 0)])).is_empty(), "a step past 127 cannot be written")
	assert_true(SheetStroke.encode(PackedVector2Array([Vector2(16384, 0)])).is_empty(), "off the sheet")
	assert_true(SheetStroke.encode(PackedVector2Array([Vector2(0.5, 0)])).is_empty(), "sheet units are whole")
	assert_eq(SheetStroke.decode(blob.slice(0, blob.size() - 1)), [], "a short blob reads as nothing")


func test_labels_count_as_strokes_and_ids_stay_their_own() -> void:
	var sheet: Sheet = Sheet.new()
	sheet.add_stroke(SheetStroke.make(1, 0, _line(Vector2(0, 0), Vector2(400, 0), 4)))
	sheet.add_label(SheetLabel.make(2, 0, Vector2(0, 512), "Here be the Stythe"))
	assert_eq(sheet.count(), 2)
	assert_true(sheet.remove(1))
	assert_false(sheet.remove(1), "gone once")
	assert_eq(sheet.count(), 1)
	assert_eq(sheet.ids_near(Rect2(0, 400, 64, 64)), [2] as Array[int], "the label's box is indexed")


func test_the_rubber_cuts_a_stroke_in_two_where_it_crosses() -> void:
	var sheet: Sheet = Sheet.new()
	sheet.add_stroke(SheetStroke.make(1, 0, _line(Vector2(0, 0), Vector2(1000, 0), 10)))
	var anyone: Callable = func(_a: int) -> bool: return true
	var change: Dictionary = sheet.rub(PackedVector2Array([Vector2(500, 0)]), 48.0, anyone, 20000, _ids())
	var removed: Array[int] = change["removed"]
	assert_eq(removed, [1] as Array[int])
	var added: Array[SheetStroke] = change["added"]
	assert_eq(added.size(), 2, "two pieces")
	assert_eq(sheet.count(), 2, "each piece counts")
	assert_eq(added[0].points[added[0].points.size() - 1], Vector2(452, 0), "cut where the rubber's edge crosses")
	assert_eq(added[1].points[0], Vector2(548, 0))
	assert_eq(added[0].points[0], Vector2(0, 0), "the rest untouched")
	assert_eq(added[1].points[added[1].points.size() - 1], Vector2(1000, 0))
	assert_eq(added[0].author, 0, "the pieces keep their author")
	assert_ne(added[0].id, added[1].id)


func test_a_long_step_is_cut_even_with_no_point_under_the_rubber() -> void:
	var sheet: Sheet = Sheet.new()
	sheet.add_stroke(SheetStroke.make(1, 0, PackedVector2Array([Vector2(0, 0), Vector2(127, 0)])))
	var anyone: Callable = func(_a: int) -> bool: return true
	var change: Dictionary = sheet.rub(PackedVector2Array([Vector2(63, 10)]), 20.0, anyone, 20000, _ids())
	var added: Array[SheetStroke] = change["added"]
	assert_eq(added.size(), 2, "the step is cut in two around the rubber")


func test_the_rubber_touching_nothing_changes_nothing() -> void:
	var sheet: Sheet = Sheet.new()
	sheet.add_stroke(SheetStroke.make(1, 0, _line(Vector2(0, 0), Vector2(1000, 0), 10)))
	var r: int = sheet.revision
	var anyone: Callable = func(_a: int) -> bool: return true
	var change: Dictionary = sheet.rub(PackedVector2Array([Vector2(500, 49)]), 48.0, anyone, 20000, _ids())
	assert_eq(Variants.array(change["removed"]).size(), 0)
	assert_eq(sheet.revision, r, "untouched")


func test_a_dot_and_a_label_go_whole() -> void:
	var sheet: Sheet = Sheet.new()
	sheet.add_stroke(SheetStroke.make(1, 0, PackedVector2Array([Vector2(10, 10)])))
	sheet.add_label(SheetLabel.make(2, 0, Vector2(0, 512), "pump"))
	var anyone: Callable = func(_a: int) -> bool: return true
	var change: Dictionary = sheet.rub(PackedVector2Array([Vector2(0, 0), Vector2(300, 512)]), 48.0, anyone, 20000, _ids())
	var removed: Array[int] = change["removed"]
	assert_eq(removed, [1, 2] as Array[int], "the dot and the touched label, whole")
	assert_eq(Variants.array(change["added"]).size(), 0)
	assert_eq(sheet.count(), 0)


func test_past_the_cap_the_whole_stroke_goes_instead_of_splitting() -> void:
	var sheet: Sheet = Sheet.new()
	sheet.add_stroke(SheetStroke.make(1, 0, _line(Vector2(0, 0), Vector2(1000, 0), 10)))
	sheet.add_stroke(SheetStroke.make(2, 0, _line(Vector2(0, 2048), Vector2(1000, 2048), 10)))
	var anyone: Callable = func(_a: int) -> bool: return true
	var change: Dictionary = sheet.rub(PackedVector2Array([Vector2(500, 0)]), 48.0, anyone, 2, _ids())
	var removed: Array[int] = change["removed"]
	assert_eq(removed, [1] as Array[int])
	assert_eq(Variants.array(change["added"]).size(), 0, "a split would make 3 of a cap of 2: the stroke goes whole")
	assert_eq(sheet.count(), 1)


func test_the_rubber_touches_only_whom_it_may() -> void:
	var sheet: Sheet = Sheet.new()
	sheet.add_stroke(SheetStroke.make(1, 0, _line(Vector2(0, 0), Vector2(1000, 0), 10)))
	sheet.add_stroke(SheetStroke.make(2, 1, _line(Vector2(0, 20), Vector2(1000, 20), 10)))
	var own: Callable = func(a: int) -> bool: return a == 1
	var change: Dictionary = sheet.rub(PackedVector2Array([Vector2(500, 10)]), 48.0, own, 20000, _ids())
	var removed: Array[int] = change["removed"]
	assert_eq(removed, [2] as Array[int], "only author 1's stroke")
	assert_true(sheet.strokes.has(1), "the other's is untouched")


func test_the_digest_follows_the_contents_not_the_order() -> void:
	var a: Sheet = Sheet.new()
	var b: Sheet = Sheet.new()
	var s1: PackedVector2Array = _line(Vector2(0, 0), Vector2(300, 0), 3)
	var s2: PackedVector2Array = _line(Vector2(0, 300), Vector2(0, 600), 3)
	a.add_stroke(SheetStroke.make(1, 0, s1))
	a.add_stroke(SheetStroke.make(2, 0, s2))
	a.add_label(SheetLabel.make(3, 0, Vector2(5, 5), "gate"))
	b.add_label(SheetLabel.make(3, -1, Vector2(5, 5), "gate"))
	b.add_stroke(SheetStroke.make(2, -1, s2))
	b.add_stroke(SheetStroke.make(1, -1, s1))
	assert_eq(a.digest(), b.digest(), "the same strokes and labels, authors unknown on a client")
	b.remove(3)
	assert_ne(a.digest(), b.digest())


func test_the_extent_covers_what_is_drawn() -> void:
	var sheet: Sheet = Sheet.new()
	assert_eq(sheet.extent(), Rect2(), "nothing drawn")
	sheet.add_stroke(SheetStroke.make(1, 0, _line(Vector2(-500, -300), Vector2(700, 900), 20)))
	var e: Rect2 = sheet.extent()
	assert_true(e.has_point(Vector2(-499, -299)) and e.has_point(Vector2(699, 899)))


func test_the_pencil_follows_spaced_and_never_snaps() -> void:
	var spacing: float = Tuning.f(&"mine.sheet_point_spacing_units")
	assert_eq(SheetOps.follow(Vector2(0, 0), Vector2(10, 0), spacing).size(), 0, "nothing until 16 units away")
	assert_eq(SheetOps.follow(Vector2(0, 0), Vector2(20.4, 0.4), spacing), PackedVector2Array([Vector2(20, 0)]), "the cursor, rounded")
	var jump: PackedVector2Array = SheetOps.follow(Vector2(0, 0), Vector2(1000, 37), spacing)
	var path: PackedVector2Array = PackedVector2Array([Vector2(0, 0)])
	path.append_array(jump)
	assert_true(SheetStroke.spaced(path, spacing), "a long jump is split into even steps of at most 127")
	assert_eq(jump[jump.size() - 1], Vector2(1000, 37), "ending at the cursor")


func test_the_straight_line_aid_draws_only_between_its_points() -> void:
	var spacing: float = Tuning.f(&"mine.sheet_point_spacing_units")
	var a: Vector2 = Vector2(-1200, 300)
	var b: Vector2 = Vector2(2500, -1700)
	var line: PackedVector2Array = SheetOps.straight(a, b, spacing)
	assert_eq(line[0], a)
	assert_eq(line[line.size() - 1], b)
	assert_true(SheetStroke.spaced(line, spacing))
	for p: Vector2 in line:
		var t: float = clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		assert_lt(p.distance_to(a.lerp(b, t)), 1.0, "every point on the chosen line, within rounding")
	assert_eq(SheetOps.straight(a, a + Vector2(5, 5), spacing), PackedVector2Array([a]), "too short: a dot")


func test_a_long_drag_chains_into_strokes_that_share_their_ends() -> void:
	var pts: PackedVector2Array = _line(Vector2(0, 0), Vector2(20000, 0), 200)
	var max_points: int = Tuning.i(&"mine.sheet_stroke_max_points")
	var parts: Array[PackedVector2Array] = SheetOps.chain(pts, max_points)
	assert_gt(parts.size(), 3)
	for i: int in parts.size():
		assert_lte(parts[i].size(), max_points)
		if i > 0:
			assert_eq(parts[i][0], parts[i - 1][parts[i - 1].size() - 1], "continuous")
	assert_eq(parts[parts.size() - 1][parts[parts.size() - 1].size() - 1], pts[pts.size() - 1])


func test_labels_are_one_line_of_at_most_40_characters() -> void:
	var cap: int = Tuning.i(&"mine.sheet_label_max_chars")
	assert_eq(cap, 40)
	assert_true(SheetOps.label_ok("x".repeat(40), cap))
	assert_false(SheetOps.label_ok("x".repeat(41), cap), "41 characters")
	assert_true(SheetOps.label_ok("é".repeat(40), cap), "an accented letter is one character")
	assert_false(SheetOps.label_ok("two\nlines", cap))
	assert_false(SheetOps.label_ok("   ", cap))
	assert_eq(SheetOps.grapheme_count(SheetOps.clip_label("y".repeat(55), cap)), 40, "the field stops at 40")
	assert_eq(SheetOps.clip_label("a\nb", cap), "a b")
