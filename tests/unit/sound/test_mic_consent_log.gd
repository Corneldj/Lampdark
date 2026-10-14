extends GutTest
## SND-10: the consent log. Each choice appends {choice, notice version, UTC timestamp, build} on
## the PC and to the backend's queue; entries are never rewritten; a raised notice version asks again.

var _dir: String = ""


func before_each() -> void:
	_dir = "user://test_mic_consent_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)


func after_each() -> void:
	for f: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(f))
	DirAccess.remove_absolute(_dir)


func _write_version(version: int) -> String:
	var v: String = _dir.path_join("version.json")
	var f: FileAccess = FileAccess.open(v, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": version}))
	f.close()
	return v


func _mode(version: int) -> MicMode:
	return MicMode.new(_dir.path_join("log.jsonl"), _dir.path_join("queue.jsonl"), _write_version(version))


func test_each_choice_appends_an_entry() -> void:
	var m: MicMode = _mode(1)
	m.set_mode(MicMode.Mode.USE)
	m.set_mode(MicMode.Mode.MUTE)
	var e: Array[Dictionary] = m.entries()
	assert_eq(e.size(), 2)
	assert_eq(str(e[0]["choice"]), "use")
	assert_eq(str(e[1]["choice"]), "mute")
	assert_eq(int(Variants.number(e[1]["notice_version"])), 1)
	assert_true(str(e[0]["utc"]).ends_with("Z"), "UTC")
	assert_eq(str(e[0]["build"]), Protocol.build_id())
	var queued: PackedStringArray = FileAccess.get_file_as_string(_dir.path_join("queue.jsonl")).split("\n", false)
	assert_eq(queued.size(), 2, "the backend's queue (STM-10 posts it)")


func test_a_later_launch_keeps_the_choice() -> void:
	var m: MicMode = _mode(1)
	m.set_mode(MicMode.Mode.USE)
	var again: MicMode = _mode(1)
	assert_eq(again.mode, MicMode.Mode.USE)
	assert_false(again.needs_choice())
	assert_false(again.first_launch())


func test_a_raised_notice_version_asks_again_and_mutes_until_then() -> void:
	var m: MicMode = _mode(1)
	m.set_mode(MicMode.Mode.USE)
	var revised: MicMode = _mode(2)
	assert_true(revised.needs_choice(), "the screen shows again at the next Play")
	assert_false(revised.first_launch(), "not a first launch: no comfort step")
	assert_eq(revised.mode, MicMode.Mode.MUTE, "until chosen under the new notice")
	revised.set_mode(MicMode.Mode.USE)
	assert_eq(revised.entries().size(), 2, "appended, the old entry kept")


func test_the_shipped_notice_has_its_version_and_text() -> void:
	assert_gt(MicMode.read_version(MicMode.VERSION_PATH), 0)
	var n: Dictionary = MicMode.notice("en")
	assert_eq(str(n["use"]), "Use my microphone")
	assert_eq(str(n["mute"]), "Mute (callouts and taps only)")
	assert_gt(Variants.array(n["notice"]).size(), 3)
	assert_eq(str(MicMode.notice("xx")["use"]), "Use my microphone", "unknown languages fall back to English")
