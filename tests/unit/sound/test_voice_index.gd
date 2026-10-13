extends GutTest
## SND-13: each file's index entry matches the file: the same bytes (SHA-256), its frame count, and a
## length its frames can hold. The index's loudness (measured on the decoded file by the import tool)
## is within +-1 LU of the band target and under SND-07's band cap. The server reads only the index:
## its packs exclude client/ and never carry .lbv files.

const TARGET: Dictionary = {"whisper": -38.0, "talk": -26.0, "shout": -16.0, "scream": -10.0}


func before_all() -> void:
	assert_true(Tuning.load_server())


func _cap(band: String) -> float:
	var headroom: float = Tuning.f(&"voice.band_cap_headroom_db")
	match band:
		"whisper":
			return Tuning.f(&"voice.threshold_talk_dbfs") + headroom
		"talk":
			return Tuning.f(&"voice.threshold_shout_dbfs") + headroom
		"shout":
			return Tuning.f(&"voice.threshold_scream_dbfs") + headroom
	return -1.0


func test_index_matches_every_file() -> void:
	var bad: Array[String] = []
	var checked: int = 0
	for voice: String in VoiceManifest.voice_ids():
		for id: String in VoiceManifest.line_ids():
			for form: String in VoiceManifest.forms_of(id):
				var e: Dictionary = VoiceManifest.entry(voice, id, form)
				var bytes: PackedByteArray = FileAccess.get_file_as_bytes(VoiceManifest.path_of(voice, id, form))
				var ctx: HashingContext = HashingContext.new()
				ctx.start(HashingContext.HASH_SHA256)
				ctx.update(bytes)
				var lbv: Dictionary = VoiceBank.parse(bytes)
				var frames: int = Variants.array(lbv.get("frames", [])).size()
				var span: int = int(Variants.number(lbv.get("samples", 0))) + int(Variants.number(lbv.get("pre_skip", 0)))
				checked += 1
				if ctx.finish().hex_encode() != str(e.get("sha256", "")):
					bad.append("%s %s.%s: bytes" % [voice, id, form])
				if frames != int(Variants.number(e.get("frames", -1))) or frames == 0:
					bad.append("%s %s.%s: frames" % [voice, id, form])
				if not ((frames - 1) * 960 < span and span <= frames * 960):
					bad.append("%s %s.%s: length" % [voice, id, form])
				if int(Variants.number(lbv.get("samples", 0))) != int(Variants.number(e.get("samples", -1))):
					bad.append("%s %s.%s: samples" % [voice, id, form])
	assert_eq(checked, 608)
	assert_eq(bad, [] as Array[String])


func test_every_file_decodes_to_its_indexed_length() -> void:
	assert_string_contains(LbOpusDecoder.version(), "1.6", "libopus 1.6, built in")
	var bad: Array[String] = []
	var decoded: int = 0
	for voice: String in VoiceManifest.voice_ids():
		for id: String in VoiceManifest.line_ids():
			for form: String in VoiceManifest.forms_of(id):
				var pcm: PackedFloat32Array = LbOpusDecoder.new().decode_lbv(FileAccess.get_file_as_bytes(VoiceManifest.path_of(voice, id, form)))
				decoded += 1
				if pcm.size() != int(Variants.number(VoiceManifest.entry(voice, id, form)["samples"])):
					bad.append("%s %s.%s: %d samples" % [voice, id, form, pcm.size()])
	assert_eq(decoded, 608)
	assert_eq(bad, [] as Array[String], "every file decodes to exactly its index's length")
	var here: PackedFloat32Array = VoiceBank.pcm("voice_4", "here", "shout")
	var peak: float = 0.0
	for x: float in here:
		peak = maxf(peak, absf(x))
	assert_gt(peak, 0.1, "a shout is audible")


func test_loudness_within_band() -> void:
	var bad: Array[String] = []
	for voice: String in VoiceManifest.voice_ids():
		for id: String in VoiceManifest.line_ids():
			for form: String in VoiceManifest.forms_of(id):
				var e: Dictionary = VoiceManifest.entry(voice, id, form)
				var band: String = str(e["band"])
				if absf(float(Variants.number(e["lufs"])) - float(Variants.number(TARGET[band]))) > 1.0:
					bad.append("%s %s.%s: %s LUFS" % [voice, id, form, e["lufs"]])
				if float(Variants.number(e["max_frame_rms_dbfs"])) > _cap(band):
					bad.append("%s %s.%s: over the %s cap" % [voice, id, form, band])
	assert_eq(bad, [] as Array[String])


func test_bands_as_the_design_says() -> void:
	assert_eq(str(VoiceManifest.entry("voice_1", "here", "whisper")["band"]), "whisper")
	assert_eq(str(VoiceManifest.entry("voice_1", "scream", "take_1")["band"]), "scream")
	assert_eq(str(VoiceManifest.entry("voice_1", "digit_4", "final")["band"]), "talk")


func test_server_builds_carry_no_voice_audio() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	assert_eq(cfg.load("res://export_presets.cfg"), OK)
	var servers: int = 0
	for section: String in cfg.get_sections():
		if not section.ends_with("]") and cfg.has_section_key(section, "name") and str(cfg.get_value(section, "name")).contains("-server-"):
			servers += 1
			assert_true(str(cfg.get_value(section, "exclude_filter")).contains("client/*"), "%s excludes client/" % cfg.get_value(section, "name"))
			assert_false(str(cfg.get_value(section, "include_filter")).contains("lbv"), "and never asks for .lbv")
	assert_eq(servers, 4)
