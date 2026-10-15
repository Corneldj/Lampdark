extends GutTest
## GEN-13: a synthetic worst-case Full run stays within its save budgets (GDD §15.9): 8 MB of diff
## log, 4 MB of map table at LFT-14's 20,000-stroke cap, 6 MB of Pocket Books at LFT-15's five
## books of 8,000 strokes. The serialised log round-trips byte for byte, and a fixed log digests to
## the same value on every platform (the round runs this file on Linux and under Wine).

## The digest of _fixed_log(), pinned: any platform or encoding difference changes it.
const FIXED_DIGEST: int = 8353528205802265120
## A Full run's worst case (Proposed): the seed harness's first 400 cells all visited and changed.
const CELLS: int = 400


func before_all() -> void:
	assert_true(Tuning.load_server())


## LFT-14's stroke at its point cap: an int16 start, then int8 deltas (Proposed encoding).
static func _stroke(n: int) -> PackedByteArray:
	var b: PackedByteArray = PackedByteArray()
	b.resize(4 + (Tuning.i(&"mine.sheet_stroke_max_points") - 1) * 2)
	for i: int in b.size():
		b[i] = (n * 31 + i * 7) % 256
	return b


## A cell as changed as play could make it: every tile smeared, 24 items lying (lamps among them),
## 8 chalk marks, 2 traps sprung, 2 doors, a fall, a phone line, 2 bodies.
static func _worst_cell(d: DiffLog, cell: Vector2i) -> void:
	for y: int in 20:
		for x: int in 20:
			d.mark_blood(cell * 20 + Vector2i(x, y), x + y)
	for i: int in 24:
		d.record(cell, DiffLog.Kind.ITEM, "p%08x%04d" % [absi(cell.x * 7919 + cell.y), i], {"where": "floor", "uid": 100000 + i,
			"kind": ItemKinds.Kind.GAUZE_LAMP, "count": 1, "x": cell.x * 20 + 10.25, "y": cell.y * 20 + 4.75, "lamp_phase": 0,
			"state": {"lit": true, "shutter": false, "wick": 2, "oil": 0.734512, "notches": 3, "hung": false}})
	for i: int in 8:
		d.record(cell, DiffLog.Kind.CHALK, "%d,%d:%d" % [cell.x * 20 + i, cell.y * 20, i % 4], {"glyph": i, "dir": i % 8})
	for i: int in 2:
		d.record(cell, DiffLog.Kind.TRAP, "trap:%d" % i, {"sprung": true, "boards": 3})
		d.record(cell, DiffLog.Kind.BARRIER, "door:%d,%d:%d" % [cell.x, cell.y, i], {"open": true})
		d.record(cell, DiffLog.Kind.BODY, "m%d" % (i + 1), {"x": 4.5, "y": 7.5, "table": false, "dead": true, "kept": false})
	d.record(cell, DiffLog.Kind.FALL, "collapse:0", {"fallen_at": 123456, "cuts": ["line:1", "line:2"]})
	d.record(cell, DiffLog.Kind.LINE, "phone:1", {"route": [[1, 2], [3, 4], [5, 6], [7, 8]], "cut_by": "collapse:0"})


func test_a_worst_case_full_run_fits_its_save_budgets() -> void:
	var d: DiffLog = DiffLog.new()
	for i: int in CELLS:
		_worst_cell(d, Vector2i(i % 20 - 10, i / 20 - 10))
	var table: DiffLog.Section = d.run_section(DiffLog.MAP_TABLE)
	for n: int in Tuning.i(&"mine.sheet_max_strokes"):
		table.put_raw("s%05d" % n, _stroke(n))
	var books: DiffLog.Section = d.run_section(DiffLog.POCKET_BOOKS)
	for miner: int in 5:
		for n: int in Tuning.i(&"mine.pocket_book_max_strokes"):
			books.put_raw("b%d:%d:%04d" % [miner, n % Tuning.i(&"mine.pocket_book_map_pages"), n], _stroke(n))
	var s: Dictionary = d.sizes()
	var mb: float = 1024.0 * 1024.0
	gut.p("diff log %.2f MB, map table %.2f MB, Pocket Books %.2f MB" % [Variants.number(s["diff_log"]) / mb,
		Variants.number(s["map_table"]) / mb, Variants.number(s["pocket_books"]) / mb])
	assert_lt(Variants.number(s["diff_log"]), Tuning.f(&"mine.diff_log_save_budget_mb") * mb, "the diff log within 8 MB")
	assert_lt(Variants.number(s["map_table"]), Tuning.f(&"mine.map_table_save_budget_mb") * mb, "the map table within 4 MB")
	assert_lt(Variants.number(s["pocket_books"]), Tuning.f(&"mine.pocket_books_save_budget_mb") * mb, "the Pocket Books within 6 MB")
	var run: RunState = RunState.create(1, ServerConfig.Mode.FRIENDS, false)
	d.compact(run)
	assert_true(d.budget_breaches.is_empty(), "no breach reported")


## A small log with every kind of value a payload carries.
static func _fixed_log() -> DiffLog:
	var d: DiffLog = DiffLog.new()
	for i: int in 30:
		var cell: Vector2i = Vector2i(i % 5 - 2, i / 5 - 3)
		d.record(cell, i % 11 as DiffLog.Kind, "k%d" % i, {"f": 1.0 / float(i + 3), "big": 0.1 * i + 1e-7, "n": -i * 1000003,
			"s": "ç%d" % i, "v": Vector2i(i, -i), "list": [i, 2.5, "x", {"z": i, "a": true}], "sn": &"name"})
		d.mark_blood(Vector2i(i * 3 - 40, i * 7 - 60), i)
	d.run_section(DiffLog.MAP_TABLE).put_raw("s1", _stroke(1))
	d.run_section(DiffLog.POCKET_BOOKS).put("b0:0", {"page": 0, "label": "the old fall"})
	return d


func test_the_log_round_trips_byte_for_byte() -> void:
	var d: DiffLog = _fixed_log()
	var bytes: PackedByteArray = d.store.serialise()
	var back: DiffLog = DiffLog.new()
	assert_true(back.deserialise(bytes))
	assert_eq(back.store.serialise(), bytes, "byte for byte")
	assert_eq(back.digest(), d.digest())
	for i: int in 30:
		var cell: Vector2i = Vector2i(i % 5 - 2, i / 5 - 3)
		assert_eq(back.payload_of(cell, i % 11 as DiffLog.Kind, "k%d" % i), d.payload_of(cell, i % 11 as DiffLog.Kind, "k%d" % i))
	assert_false(back.deserialise(bytes.slice(0, bytes.size() - 1)), "a cut save is refused")
	assert_eq(back.store.record_count(), 0, "and leaves nothing half-read")


func test_the_same_log_digests_alike_on_every_platform() -> void:
	var digest: int = _fixed_log().digest()
	gut.p("fixed log digest: %d (%s)" % [digest, OS.get_name()])
	assert_eq(digest, FIXED_DIGEST, "pinned; Linux and Windows must agree")
