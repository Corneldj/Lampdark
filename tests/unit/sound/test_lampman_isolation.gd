extends GutTest
## SND-13 (Gameplay §7.3, §9.2): the lampman is heard only above ground. Only the Pithead and Lamp
## Check (client/pithead/) may reach his bank; no mine code, illusion or callout can. No record can
## name his lines: the lampman is no voice (wire_voice), his remarks and first-run line have no wire
## number, and the voice bank only ever loads character voices.

const ALLOWED: Array[String] = ["res://client/pithead/", "res://tests/", "res://tools/", "res://addons/"]


func _sources(dir: String, out: Array[String]) -> void:
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd") or f.ends_with(".tscn") or f.ends_with(".tres"):
			out.append(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			_sources(dir.path_join(d), out)


func test_only_the_pithead_reaches_the_lampman() -> void:
	var files: Array[String] = []
	_sources("res://", files)
	assert_gt(files.size(), 100)
	var offenders: Array[String] = []
	for path: String in files:
		var allowed: bool = false
		for prefix: String in ALLOWED:
			if path.begins_with(prefix):
				allowed = true
		if allowed:
			continue
		var code: String = FileAccess.get_file_as_string(path)
		if code.contains("LampmanBank") or code.contains("audio/lampman"):
			offenders.append(path)
	assert_eq(offenders, [] as Array[String], "the lampman bank is reachable only from client/pithead/")


func test_no_record_can_name_a_lampman_line() -> void:
	assert_eq(VoiceManifest.wire_voice("lampman"), -1, "the lampman is not a voice")
	for line: Dictionary in VoiceManifest.lampman_lines():
		var id: String = str(line["line_id"])
		if id.begins_with("digit_"):
			continue  # a character voice's digit shares the id; records reach only the character's file
		assert_eq(VoiceManifest.wire_line(id), -1, "%s has no wire number" % id)
	for n: int in VoiceManifest.line_ids().size():
		var path: String = VoiceManifest.path_of("voice_1", VoiceManifest.line_of_wire(n), "talk")
		assert_true(path.begins_with(VoiceManifest.VOICES_DIR), "every wire line resolves under the character voices")
	assert_eq(VoiceManifest.wire_voice("voice_8"), 7)
	assert_false(VoiceManifest.path_of("voice_1", "digit_1", "final").contains("lampman"))


func test_the_pithead_can_play_him() -> void:
	var s: AudioStream = LampmanBank.first_run()
	assert_not_null(s, "the first-run line")
	assert_eq(LampmanBank.number("114").size(), 3)
	assert_not_null(LampmanBank.remark("roof_fall"))
