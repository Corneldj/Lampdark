extends GutTest
## UI-03: a callout shows its words (a word with too few of its frames as a gap), its band and its
## character voice's descriptor; never a player's name, a miner's name or a lamp number.


func before_all() -> void:
	assert_true(Tuning.load_client())


func test_words_band_and_voice() -> void:
	var sys: CaptionSystem = CaptionSystem.new()
	var key: String = _first_callout_key()
	assert_false(key.is_empty())
	var words: PackedStringArray = UiText.text(key).split(" ", false)
	var all: PackedFloat32Array = PackedFloat32Array()
	all.resize(words.size())
	all.fill(1.0)
	sys.on_callout(key, all, 3, "voice_2", Vector2(0, -5), 0.8, 0.0)
	assert_eq(str(sys.visible_lines()[0]["text"]), "%s (shouted, the second voice)" % UiText.text(key))
	assert_almost_eq(float(Variants.number(sys.visible_lines()[0]["bearing"])), 270.0, 0.01, "north is up the screen")


func test_dropped_words_show_as_gaps() -> void:
	var gap: String = UiText.text("caption.word_gap")
	assert_eq(CaptionSystem.callout_words("Moth on the left", PackedFloat32Array([0.2, 1.0, 0.1, 0.9])), "%s on %s left" % [gap, gap])
	assert_eq(CaptionSystem.callout_words("Moth on the left", PackedFloat32Array([1.0, 0.4, 0.3, 1.0])), "Moth %s left" % gap, "one gap for a run")
	assert_eq(CaptionSystem.callout_words("Douse", PackedFloat32Array([0.5])), "Douse", "half its frames is enough")


func test_no_caption_names_anyone() -> void:
	var sys: CaptionSystem = CaptionSystem.new()
	var labels: Array[String] = []
	var doc: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string("res://data/voices/manifest.json")))
	for raw: Variant in Variants.array(doc["voices"]):
		labels.append(str(Variants.dict(raw).get("label", "")).to_lower())
	var digits: RegEx = RegEx.create_from_string("[0-9]")
	var t: float = 0.0
	for voice_id: String in VoiceManifest.voice_ids():
		for key: String in _callout_keys():
			sys.on_callout(key, PackedFloat32Array(), 2, voice_id, null, 0.5, t)
			t += 10.0
			sys.tick(t)
	assert_gt(sys.history.size(), 0)
	for h: Dictionary in sys.history:
		var text: String = str(h["text"]).to_lower()
		assert_null(digits.search(text), "no lamp number: %s" % text)
		for label: String in labels:
			assert_false(not label.is_empty() and text.contains(label), "no casting label: %s" % text)


func _callout_keys() -> Array[String]:
	var out: Array[String] = []
	var doc: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string("res://data/text/callouts/en.json")))
	for raw: Variant in Variants.dict(doc.get("strings", {})).keys():
		out.append(str(raw))
	out.sort()
	return out


func _first_callout_key() -> String:
	for k: String in _callout_keys():
		if UiText.text(k).split(" ", false).size() >= 1:
			return k
	return ""
