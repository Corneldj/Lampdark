extends "res://tests/scenario/kit/scenario_test.gd"
## NET-09: a saved run resumes in the mine it began in. Its header names the generator and template
## set; a build that does not carry them refuses it with a plain message (GEN-04 carries the previous
## update's; until it lands, the fixed maps are the generators and there are no templates). A save of
## GEN-03's grey box resumes with every cell identical (golden digests), and a real server started
## with --resume picks the run up where its save left it.

const S = preload("res://tests/scenario/net/save_world.gd")
const MAP: String = "m1_greybox"


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_the_versions_a_save_resumes_on_are_checked() -> void:
	var ok: Dictionary = {"generator": "fixed:" + MAP, "templates": "none", "mode": ServerConfig.Mode.FRIENDS}
	assert_eq(SaveResume.refusal(ok), "")
	assert_eq(SaveResume.refusal({"generator": "none", "templates": "none", "mode": ServerConfig.Mode.NIGHTSHIFT}), "")
	var refused: Array[Dictionary] = [
		{"generator": "fixed:a_mine_long_gone", "templates": "none", "mode": 0},
		{"generator": "gen:0.9", "templates": "none", "mode": 0},
		{"generator": "fixed:" + MAP, "templates": "set:3", "mode": 0},
		{"generator": "fixed:" + MAP, "templates": "none", "mode": ServerConfig.Mode.PUBLIC}]
	for h: Dictionary in refused:
		var why: String = SaveResume.refusal(h)
		gut.p("%s -> %s" % [str(h), why])
		assert_ne(why, "", "refused: %s" % str(h))
		assert_false(why.contains("fixed:") or why.contains("Error"), "plain words")


func test_a_grey_box_save_resumes_in_the_same_mine() -> void:
	S.clear(971)
	var s: Scenario = make({"seed": 971, "fixture": MAP, "saves": true})
	s.run.header.map_name = MAP
	var ann: MinerHandle = s.add_miner("ann", Vector2i(6, 6))
	ann.brain = null
	assert_true(S.until_saved(s, 1))
	var golden: Dictionary = {}
	for c: Vector2i in s.mine.native.loaded_cells():
		golden[c] = s.mine.native.digest(c)
	assert_gt(golden.size(), 0)
	var path: String = S.snapshot_path(s)
	assert_eq(str(SaveContainer.read_header(FileAccess.get_file_as_bytes(path))["generator"]), "fixed:" + MAP)
	S.kill(s)
	var opened: Dictionary = SaveResume.open_file(path)
	assert_true(Variants.flag(opened["ok"]), str(opened["message"]))
	var b: Scenario = make({"seed": 971, "fixture": MAP, "saves": true})
	SaveResume.apply(b.run, b.net, opened)
	var same: int = 0
	for raw: Variant in golden.keys():
		var c: Vector2i = raw
		if b.mine.native.digest(c) == golden[c]:
			same += 1
	assert_eq(same, golden.size(), "every cell identical")
	assert_eq(b.run.header.map_name, MAP)


func test_a_real_server_resumes_from_its_save() -> void:
	var dir: String = ProjectSettings.globalize_path("user://net09_server_resume")
	S._remove_tree(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var out: Array = []
	var args: PackedStringArray = PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--",
		"--server", "--map", MAP, "--port", str(29000 + randi() % 900), "--save-dir", dir, "--exit-after-ticks", "40"])
	var code: int = OS.execute(OS.get_executable_path(), args, out, true)
	assert_eq(code, 0, "the first server ran and ended")
	var runs: PackedStringArray = DirAccess.get_directories_at(dir)
	assert_eq(runs.size(), 1, "one run's folder, named by its UUID")
	if runs.size() != 1:
		gut.p(str(out))
		return
	var uuid: String = runs[0]
	assert_eq(uuid.length(), 36, "a UUID")
	var path: String = dir.path_join(uuid).path_join(Saves.SNAPSHOT_FILE)
	assert_true(FileAccess.file_exists(path), "saved as it ended")
	var out2: Array = []
	var args2: PackedStringArray = PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--",
		"--server", "--resume", path, "--port", str(29000 + randi() % 900), "--save-dir", dir, "--exit-after-ticks", "5"])
	var code2: int = OS.execute(OS.get_executable_path(), args2, out2, true)
	var text: String = "\n".join(PackedStringArray(out2))
	assert_eq(code2, 0, "the second server resumed and ended")
	assert_true(text.contains("resumed run %s at tick 40" % uuid), "picked up at the save's tick")
	if not text.contains("resumed run"):
		gut.p(text.right(3000))
	# A tampered save is refused by the server, with the reason.
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	bytes[bytes.size() - 10] = bytes[bytes.size() - 10] ^ 0x40
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	var out3: Array = []
	args2[args2.find(str(args2[args2.find("--port") + 1]))] = str(29900 + randi() % 90)
	var code3: int = OS.execute(OS.get_executable_path(), args2, out3, true)
	assert_ne(code3, 0, "refused")
	assert_true("\n".join(PackedStringArray(out3)).contains("cannot be resumed"), "with the reason")
