extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-14 with GEN-13 and NET-09: the sheet lives in the diff log's run-level section (Gameplay
## §12.6), so cells evicting and the log compacting leave it as it was, and a knock-off save or an
## abnormal end's last snapshot brings it back whole on resume, to every client that rejoins.

const T = preload("res://tests/scenario/sheets/table_world.gd")
const S = preload("res://tests/scenario/net/save_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _draw_some(s: Scenario, ann: MinerHandle) -> void:
	T.open_table(s, ann)
	T.draw(ann, T.line(Vector2(0, 0), Vector2(600, 0), 6))
	T.draw(ann, T.line(Vector2(0, 300), Vector2(600, 300), 6))
	ann.connection.sheet.commit_label(Vector2(0, 600), "Here be the Stythe", Transport.now_usec())
	s.step(5)
	ann.connection.sheet.rub(PackedVector2Array([Vector2(300, 0)]))
	s.step(5)
	assert_eq(s.run.sheets.table.sheet.count(), 4, "two lines, one in two, and a label")


func test_eviction_and_compaction_leave_the_sheet_as_it_was() -> void:
	var s: Scenario = make(S.cfg(1701))
	var ann: MinerHandle = S.miner(s, "ann", Vector2i(3, 3))
	_draw_some(s, ann)
	var digest: int = s.run.sheets.table.sheet.digest()
	var bytes: int = s.run.diff_log.sizes()["map_table"]
	for c: Vector2i in s.run.mine.native.loaded_cells():
		s.run.diff_log.evict(s.run, c)
	s.run.diff_log.compact(s.run)
	s.step(5)
	var after: int = s.run.diff_log.sizes()["map_table"]
	assert_eq(after, bytes, "the section untouched")
	assert_eq(s.run.sheets.table.sheet.digest(), digest)


func _resume_and_check(seed_value: int, write: Callable, file: String) -> void:
	S.clear(seed_value)
	var s: Scenario = make(S.cfg(seed_value))
	var ann: MinerHandle = S.miner(s, "ann", Vector2i(3, 3))
	_draw_some(s, ann)
	var digest: int = s.run.sheets.table.sheet.digest()
	write.call(s)
	var path: String = s.run.saves.run_dir().path_join(file)
	S.kill(s)
	var b: Scenario = S.resume(make, seed_value, path)[0]
	assert_eq(b.run.sheets.table.sheet.digest(), digest, "the sheet as it was")
	assert_eq(b.run.sheets.table.authors, PackedStringArray(["ann"]), "with who drew it")
	var back: MinerHandle = b.rejoin("ann")
	b.step(40)
	assert_eq(back.connection.sheet.sheet.digest(), digest, "and on Ann's client once she rejoins")
	T.open_table(b, back)
	T.draw(back, T.line(Vector2(0, 900), Vector2(600, 900), 6))
	b.step(10)
	assert_eq(b.run.sheets.table.sheet.count(), 5, "drawing goes on")
	var ids: Array = b.run.sheets.table.sheet.strokes.keys()
	ids.append_array(b.run.sheets.table.sheet.labels.keys())
	var unique: Dictionary = {}
	for raw: Variant in ids:
		unique[raw] = true
	assert_eq(unique.size(), ids.size(), "no id reused")


func test_a_knock_off_save_brings_it_back() -> void:
	var knock_off: Callable = func(s: Scenario) -> void:
		s.run.saves.knockoff(s.run)
		s.run.saves.flush()
	_resume_and_check(1702, knock_off, Saves.KNOCKOFF_FILE)


func test_an_abnormal_end_brings_it_back() -> void:
	_resume_and_check(1703, func(s: Scenario) -> void: s.run.saves.end_abnormally(s.run, "host quit"), Saves.SNAPSHOT_FILE)
