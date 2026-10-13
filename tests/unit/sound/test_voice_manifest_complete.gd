extends GutTest
## SND-13 (GDD §14.2, Gameplay §6.7): the manifest lists eight voices x 16 callout lines x 3 bands,
## 10 digits x 2 forms, 6 miner sounds and the roll-call fragments, and every file exists for every
## voice and form; no other file sits beside them. Callouts last voice.callout_max_duration_s or less.
## The five copyable lines are flagged for CRT-10. Every line has its subtitle, and no text holds a name.

const FIXTURE_NAMES: String = "res://tests/fixtures/voices/names_sample.json"
const REAL_NAMES: String = "res://data/text/names.json"


func before_all() -> void:
	assert_true(Tuning.load_server())


func _kinds() -> Dictionary:
	var by_kind: Dictionary = {}
	for id: String in VoiceManifest.line_ids():
		var kind: String = str(VoiceManifest.line_info(id)["kind"])
		if not by_kind.has(kind):
			by_kind[kind] = []
		Variants.array(by_kind[kind]).append(id)
	return by_kind


func test_counts() -> void:
	assert_eq(VoiceManifest.voice_ids().size(), 8, "eight character voices")
	var k: Dictionary = _kinds()
	var callouts: int = Variants.array(k["warning"]).size() + Variants.array(k["order"]).size() + Variants.array(k["job"]).size()
	assert_eq(callouts, 16, "16 callout lines")
	assert_eq(Variants.array(k["warning"]).size(), 3, "the three warnings, spoken as full rules")
	for kind: String in ["warning", "order", "job"]:
		for id: Variant in Variants.array(k[kind]):
			assert_eq(VoiceManifest.forms_of(str(id)), PackedStringArray(["whisper", "talk", "shout"]), "%s at three bands" % id)
	assert_eq(Variants.array(k["digit"]).size(), 10, "digits 0-9")
	for id: Variant in Variants.array(k["digit"]):
		assert_eq(VoiceManifest.forms_of(str(id)), PackedStringArray(["continuing", "final"]))
	assert_eq(Variants.array(k["miner_sound"]).size(), 6, "scream, gasp, cough, moan, panting, the trapped cry")
	assert_eq(Variants.array(k["roll_call"]), ["roll_lamp", "roll_all_right"], "'Lamp' and 'all right'")


func test_every_file_for_every_voice() -> void:
	var expected: int = 0
	var missing: Array[String] = []
	for voice: String in VoiceManifest.voice_ids():
		for id: String in VoiceManifest.line_ids():
			for form: String in VoiceManifest.forms_of(id):
				expected += 1
				var path: String = VoiceManifest.path_of(voice, id, form)
				if not FileAccess.file_exists(path) or VoiceManifest.entry(voice, id, form).is_empty():
					missing.append(path)
	assert_eq(expected, 8 * 76, "48 callout files, 20 digits, 6 miner sounds and 2 roll-call fragments per voice")
	assert_eq(missing, [] as Array[String], "every file and index entry present")
	var found: int = 0
	for voice: String in DirAccess.get_directories_at(VoiceManifest.VOICES_DIR):
		for f: String in DirAccess.get_files_at(VoiceManifest.VOICES_DIR + "/" + voice):
			if f.ends_with(".lbv"):
				found += 1
	assert_eq(found, expected, "no stray file")
	for line: Dictionary in VoiceManifest.lampman_lines():
		for form: Variant in Variants.array(line["forms"]):
			assert_true(FileAccess.file_exists("%s/%s.%s.ogg" % [LampmanBank.DIR, line["line_id"], form]), "lampman %s" % line["line_id"])


func test_callouts_short_enough() -> void:
	var max_s: float = Tuning.f(&"voice.callout_max_duration_s")
	for voice: String in VoiceManifest.voice_ids():
		for id: String in VoiceManifest.line_ids():
			if not ["warning", "order", "job"].has(str(VoiceManifest.line_info(id)["kind"])):
				continue
			for form: String in VoiceManifest.forms_of(id):
				assert_lte(VoiceManifest.duration_s(voice, id, form), max_s, "%s %s.%s" % [voice, id, form])


func test_copyable_lines_flagged() -> void:
	var flagged: Array[String] = []
	for id: String in VoiceManifest.line_ids():
		if Variants.flag(VoiceManifest.line_info(id).get("copyable_by_tapper", false)):
			flagged.append(id)
	flagged.sort()
	var want: Array[String] = VoiceManifest.COPYABLE.duplicate()
	want.sort()
	assert_eq(flagged, want, "'Here!', 'Help!', 'Is that you?', 'Count off!', 'Douse!'")


func test_every_line_has_a_subtitle() -> void:
	var strings: Dictionary = Variants.dict(Variants.dict(JSON.parse_string(FileAccess.get_file_as_string("res://data/text/callouts/en.json")))["strings"])
	for id: String in VoiceManifest.line_ids():
		assert_true(strings.has(str(VoiceManifest.line_info(id)["text_key"])), id)
	assert_eq(str(strings["callout.tapping"]), "'Tapping! Shut up and get off the walls!'", "the warning is its full rule")


static func _names() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for path: String in [FIXTURE_NAMES, REAL_NAMES]:
		if not FileAccess.file_exists(path):
			continue
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		var list: Array = Variants.array(Variants.dict(d).get("names", [])) if d is Dictionary else Variants.array(d)
		for n: Variant in list:
			out.append(str(n))
	return out


static func _holds_name(text: String, names: PackedStringArray) -> String:
	var words: PackedStringArray = text.to_lower().replace("'", " ").replace(",", " ").replace("!", " ").replace("?", " ").replace(".", " ").split(" ", false)
	for n: String in names:
		if words.has(n.to_lower()):
			return n
	return ""


func test_no_text_holds_a_name() -> void:
	var names: PackedStringArray = _names()
	assert_gt(names.size(), 20)
	assert_eq(_holds_name("'Here, Ada!'", names), "Ada", "the check catches a planted name")
	var texts: Array[String] = []
	for path: String in ["res://data/text/callouts/en.json", "res://data/text/lampman/lines.json", "res://data/text/lampman/remarks.json"]:
		for v: Variant in Variants.dict(Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(path)))["strings"]).values():
			texts.append(str(v))
	var placeholder: Dictionary = Variants.dict(Variants.dict(Variants.dict(JSON.parse_string(
		FileAccess.get_file_as_string("res://tools/build/voice_import/settings.json")))["placeholder"])["spoken"])
	for v: Variant in placeholder.values():
		texts.append(str(v))
	texts.append(FileAccess.get_file_as_string(VoiceManifest.MANIFEST))
	for t: String in texts:
		assert_eq(_holds_name(t, names), "", "no name in: %s" % t.left(60))
