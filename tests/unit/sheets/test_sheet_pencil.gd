extends GutTest
## LFT-14: the table's tools on the client (SheetPencil, ClientSheet). The pencil follows the
## pointer, spaced, and chains a long drag into strokes that share their ends; the straight-line
## aid draws only between the two points chosen, never where the pointer wandered between, and
## nothing snaps; a press without a drag is a dot; the rubber's path goes in overlapping steps of
## half its radius; at the cap the pencil marks nothing; and the sheet never gains a stroke without
## the pointer.

## Every SHEET message the client would send: [lane, ops].
var sent: Array[Array] = []


func before_all() -> void:
	assert_true(Tuning.load_client())


func _sheet() -> ClientSheet:
	sent.clear()
	var cs: ClientSheet = ClientSheet.new()
	cs.send = func(lane: int, payload: PackedByteArray) -> Error:
		sent.append([lane, SheetCodec.decode(payload)])
		return OK
	return cs


func _ops(kind: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m: Array in sent:
		for d: Dictionary in Variants.array(m[1]):
			if int(Variants.number(d["op"])) == kind:
				out.append(d)
	return out


func _points(d: Dictionary) -> PackedVector2Array:
	var p: PackedVector2Array = d["points"]
	return p


func test_the_pencil_follows_the_pointer_and_chains_a_long_drag() -> void:
	var cs: ClientSheet = _sheet()
	var pencil: SheetPencil = SheetPencil.new(cs)
	var t: int = 1000000
	pencil.press(SheetPencil.Tool.PENCIL, Vector2(0, 0), t)
	for i: int in range(1, 201):
		t += 5000
		pencil.drag(Vector2(i * 30.0, sin(i * 0.2) * 200.0), t)
		cs.pump(t)  # the connection's poll, each frame
	pencil.release(Vector2(6000, 0), t)
	cs.pump(t + 5000000)
	var commits: Array[Dictionary] = _ops(SheetCodec.Op.COMMIT_STROKE)
	var max_points: int = Tuning.i(&"mine.sheet_stroke_max_points")
	assert_gt(commits.size(), 2, "chained")
	for i: int in commits.size():
		var pts: PackedVector2Array = _points(commits[i])
		assert_lte(pts.size(), max_points)
		assert_true(SheetStroke.spaced(pts, Tuning.f(&"mine.sheet_point_spacing_units")), "spaced as the server checks")
		if i > 0:
			var prev: PackedVector2Array = _points(commits[i - 1])
			assert_eq(pts[0], prev[prev.size() - 1], "each starts where the last ended")
	var first: PackedVector2Array = _points(commits[0])
	assert_eq(first[0], Vector2(0, 0), "from where the pencil went down")
	var last: PackedVector2Array = _points(commits[commits.size() - 1])
	assert_eq(last[last.size() - 1], Vector2(6000, 0), "to where it came up")
	assert_gt(_ops(SheetCodec.Op.SKETCH).size(), 2, "and sent as it was made")


func test_the_straight_line_aid_draws_only_between_the_chosen_points() -> void:
	var cs: ClientSheet = _sheet()
	var pencil: SheetPencil = SheetPencil.new(cs)
	pencil.straight_lines = true
	var t: int = 1000000
	pencil.press(SheetPencil.Tool.PENCIL, Vector2(-500, 200), t)
	for i: int in 50:
		t += 10000
		pencil.drag(Vector2(i * 37.0 - 900.0, 3000.0 * (1 if i % 2 == 0 else -1)), t)
	pencil.release(Vector2(2700, -1300), t)
	cs.pump(t + 5000000)
	assert_eq(_ops(SheetCodec.Op.SKETCH).size(), 0, "a straight line is sent only once it is chosen")
	var a: Vector2 = Vector2(-500, 200)
	var b: Vector2 = Vector2(2700, -1300)
	var all: PackedVector2Array = PackedVector2Array()
	for d: Dictionary in _ops(SheetCodec.Op.COMMIT_STROKE):
		all.append_array(_points(d))
	assert_gt(all.size(), 2)
	for p: Vector2 in all:
		var u: float = clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		assert_lt(p.distance_to(a.lerp(b, u)), 1.0, "every point on the chosen line, none where the pointer wandered")
	assert_true(all.has(a) and all.has(b), "from the first point to the second, nothing snapped")


func test_a_press_without_a_drag_is_a_dot() -> void:
	var cs: ClientSheet = _sheet()
	var pencil: SheetPencil = SheetPencil.new(cs)
	pencil.press(SheetPencil.Tool.PENCIL, Vector2(40.4, -7.6), 1000)
	pencil.release(Vector2(40.4, -7.6), 2000)
	var commits: Array[Dictionary] = _ops(SheetCodec.Op.COMMIT_STROKE)
	assert_eq(commits.size(), 1)
	assert_eq(_points(commits[0]), PackedVector2Array([Vector2(40, -8)]))


func test_the_rubber_sweeps_its_path_in_half_radius_steps() -> void:
	var cs: ClientSheet = _sheet()
	var pencil: SheetPencil = SheetPencil.new(cs)
	var t: int = 1000000
	pencil.press(SheetPencil.Tool.RUBBER, Vector2(0, 0), t)
	for i: int in range(1, 30):
		t += 30000
		pencil.drag(Vector2(i * 70.0, 0), t)
	pencil.release(Vector2(2100, 0), t)
	var rubs: Array[Dictionary] = _ops(SheetCodec.Op.RUB)
	assert_gt(rubs.size(), 2, "sent as it goes")
	var path: PackedVector2Array = PackedVector2Array()
	for d: Dictionary in rubs:
		var pts: PackedVector2Array = _points(d)
		if not path.is_empty():
			assert_eq(pts[0], path[path.size() - 1], "each batch starts where the last ended")
		path.append_array(pts)
	var half: float = Tuning.f(&"mine.sheet_rubber_radius_units") * 0.5
	for i: int in range(1, path.size()):
		assert_lte(path[i].distance_to(path[i - 1]), half + 0.75, "no gap the rubber skips")
	assert_eq(path[path.size() - 1], Vector2(2100, 0))
	assert_eq(_ops(SheetCodec.Op.COMMIT_STROKE).size(), 0, "rubbing draws nothing")


func test_at_the_cap_the_pencil_marks_nothing() -> void:
	var cs: ClientSheet = _sheet()
	cs.on_message(SheetCodec.full(true), 0)
	var pencil: SheetPencil = SheetPencil.new(cs)
	pencil.press(SheetPencil.Tool.PENCIL, Vector2(0, 0), 1000)
	pencil.drag(Vector2(400, 0), 2000)
	pencil.release(Vector2(400, 0), 3000)
	assert_eq(pencil.label("pump", 4000), -1, "no label either")
	cs.pump(9000000)
	assert_eq(sent.size(), 0, "nothing sent, nothing shown")
	assert_eq(cs.pending.size(), 0)
	pencil.press(SheetPencil.Tool.RUBBER, Vector2(0, 0), 5000)
	pencil.release(Vector2(0, 0), 6000)
	assert_eq(_ops(SheetCodec.Op.RUB).size(), 1, "the rubber still works")


func test_the_sheet_never_gains_a_stroke_without_the_pointer() -> void:
	var cs: ClientSheet = _sheet()
	var pencil: SheetPencil = SheetPencil.new(cs)
	for i: int in 200:
		cs.pump(i * 50000)
	pencil.cancel()
	cs.pump(20000000)
	assert_eq(sent.size(), 0, "no input, no op")
	assert_eq(cs.sheet.count() + cs.pending.size(), 0)


func test_labels_stop_at_the_cap_on_the_client() -> void:
	var cs: ClientSheet = _sheet()
	var pencil: SheetPencil = SheetPencil.new(cs)
	pencil.at = Vector2(10, 20)
	assert_gt(pencil.label("x".repeat(55), 1000), 0)
	var labels: Array[Dictionary] = _ops(SheetCodec.Op.COMMIT_LABEL)
	assert_eq(labels.size(), 1)
	assert_eq(str(labels[0]["text"]).length(), 40, "the client never sends a 41-character label")
