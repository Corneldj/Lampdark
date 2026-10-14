extends GutTest
## SND-06: calibration (GDD §15.5): the formula, clamps, retries, warnings and per-device storage;
## voice bands and push-to-talk. Takes are fed as 1 kHz tones at a known speech-band level.

var _dir: String = ""


func before_all() -> void:
	Tuning.load_client()


func before_each() -> void:
	_dir = "user://test_calibration_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)


func after_each() -> void:
	for f: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(f))
	DirAccess.remove_absolute(_dir)


## One 20 ms frame of a 1 kHz tone at `dbfs` RMS.
static func frame(dbfs: float, phase: int = 0) -> PackedFloat32Array:
	var pcm: PackedFloat32Array = PackedFloat32Array()
	pcm.resize(960)
	var amp: float = pow(10.0, dbfs / 20.0) * sqrt(2.0)
	for i: int in 960:
		pcm[i] = amp * sin(TAU * 1000.0 * float(phase * 960 + i) / 48000.0)
	return pcm


## A take: `seconds` of speech at `dbfs`, then `quiet` seconds of silence.
func take(c: Calibration, kind: Calibration.Kind, dbfs: float, seconds: float = 1.5, erl: float = -1.0) -> Dictionary:
	c.capture_register(kind)
	for i: int in roundi(seconds * 50.0):
		c.feed(frame(dbfs, i), erl)
	return c.end_register()


func _cal() -> Calibration:
	return Calibration.new(_dir.path_join("calibration.json"))


func test_the_worked_example() -> void:
	var c: Calibration = _cal()
	assert_eq(int(Variants.number(take(c, Calibration.Kind.NORMAL, -32.0)["result"])), Calibration.Result.PASS)
	assert_eq(int(Variants.number(take(c, Calibration.Kind.WHISPER, -48.0)["result"])), Calibration.Result.PASS)
	assert_eq(int(Variants.number(take(c, Calibration.Kind.CALLED, -14.0)["result"])), Calibration.Result.PASS)
	var r: Dictionary = c.finish("usb-1")
	var t: PackedFloat32Array = r["thresholds"]
	assert_eq(int(Variants.number(r["result"])), Calibration.Result.PASS, "no clamp")
	assert_almost_eq(t[0], -50.0, 0.01, "whisper keeps its default")
	assert_almost_eq(t[1], -37.3, 0.25, "talk two-thirds from whispered to normal (the takes read ~0.1 dB under nominal)")
	assert_almost_eq(t[2], -23.0, 0.25, "shout midway between normal and called")
	assert_almost_eq(t[3], -8.0, 0.25, "scream 6 dB above called")


func test_the_formula_alone() -> void:
	var t: PackedFloat32Array = Calibration.formula(-48.0, -32.0, -14.0)
	assert_almost_eq(t[1], -37.33, 0.01)
	assert_almost_eq(t[2], -23.0, 0.001)
	assert_almost_eq(t[3], -8.0, 0.001)


func test_clamps_hold_each_threshold_within_6_db_and_say_so() -> void:
	var c: Calibration = _cal()
	take(c, Calibration.Kind.WHISPER, -58.0)
	take(c, Calibration.Kind.NORMAL, -50.0)
	take(c, Calibration.Kind.CALLED, -40.0)
	var r: Dictionary = c.finish("quiet-mic")
	var t: PackedFloat32Array = r["thresholds"]
	assert_eq(int(Variants.number(r["result"])), Calibration.Result.CLAMPED)
	var d: PackedFloat32Array = VoiceBands.defaults()
	for i: int in 4:
		assert_between(t[i], d[i] - 6.0 - 0.001, d[i] + 6.0 + 0.001, "threshold %d within 6 dB of its default" % i)
	assert_almost_eq(t[1], -46.0, 0.01, "talk clamped: nobody calibrates a shout into a whisper")


func test_retry_for_too_little_speech() -> void:
	var c: Calibration = _cal()
	assert_eq(int(Variants.number(take(c, Calibration.Kind.NORMAL, -32.0, 0.3)["result"])), Calibration.Result.RETRY, "0.3 s of speech")
	c.capture_register(Calibration.Kind.NORMAL)
	for i: int in 75:
		c.feed(frame(-70.0, i))  # under the -60 floor: nothing said
	assert_eq(int(Variants.number(c.end_register()["result"])), Calibration.Result.RETRY)


func test_retry_for_medians_out_of_order() -> void:
	var c: Calibration = _cal()
	take(c, Calibration.Kind.NORMAL, -32.0)
	assert_eq(int(Variants.number(take(c, Calibration.Kind.WHISPER, -30.0)["result"])), Calibration.Result.RETRY, "whispered louder than normal")
	assert_eq(int(Variants.number(take(c, Calibration.Kind.CALLED, -35.0)["result"])), Calibration.Result.RETRY, "called quieter than normal")
	assert_eq(int(Variants.number(c.finish("x")["result"])), Calibration.Result.RETRY, "a take missing: no thresholds yet")


func test_warnings_for_speakers_and_automatic_gain() -> void:
	var c: Calibration = _cal()
	c.speakers_setting = true
	take(c, Calibration.Kind.WHISPER, -48.0)
	take(c, Calibration.Kind.NORMAL, -32.0)
	take(c, Calibration.Kind.CALLED, -28.0)  # only 4 dB above normal: automatic gain
	var w: Array = c.finish("deck")["warnings"]
	assert_true(w.has(Calibration.WARN_SPEAKERS), "the speakers setting")
	assert_true(w.has(Calibration.WARN_AGC), "called - normal < 6 dB")
	var e: Calibration = _cal()
	take(e, Calibration.Kind.WHISPER, -48.0, 1.5, 9.0)  # SND-05 hears the game 9 dB down: speakers
	take(e, Calibration.Kind.NORMAL, -32.0)
	take(e, Calibration.Kind.CALLED, -14.0)
	var we: Array = e.finish("laptop")["warnings"]
	assert_eq(we, [Calibration.WARN_SPEAKERS], "the echo estimate alone warns; a 18 dB called margin does not")


func test_only_thresholds_date_and_warnings_are_kept_per_device() -> void:
	var c: Calibration = _cal()
	take(c, Calibration.Kind.WHISPER, -48.0)
	take(c, Calibration.Kind.NORMAL, -32.0)
	take(c, Calibration.Kind.CALLED, -14.0)
	c.finish("usb-1")
	var path: String = _dir.path_join("calibration.json")
	var stored: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
	assert_eq(stored.keys(), ["usb-1"])
	var keys: Array = Variants.dict(stored["usb-1"]).keys()
	keys.sort()
	assert_eq(keys, ["date", "thresholds", "warnings"], "no audio, no medians, no levels")
	assert_lt(FileAccess.get_file_as_bytes(path).size(), 400, "a few numbers, not a recording")
	assert_true(Calibration.is_calibrated("usb-1", path))
	assert_almost_eq(Calibration.thresholds_for("usb-1", path)[1], -37.3, 0.25)
	assert_false(Calibration.is_calibrated("bt-2", path))
	assert_eq(Calibration.thresholds_for("bt-2", path), VoiceBands.defaults(), "a new device: the defaults")


func test_a_new_device_starts_on_defaults_with_needs_calibration() -> void:
	var path: String = _dir.path_join("calibration.json")
	var c: Calibration = Calibration.new(path)
	take(c, Calibration.Kind.WHISPER, -48.0)
	take(c, Calibration.Kind.NORMAL, -32.0)
	take(c, Calibration.Kind.CALLED, -14.0)
	c.finish("usb-1")
	var v: VoiceCapture = VoiceCapture.new("fake")
	v.tap_far_end = false
	v.calibration_path = path
	v.mic_mode = func() -> int: return MicMode.Mode.USE
	v.native.fake_add_device("usb-1", "USB headset", true)
	v.voice_live = true
	v.tick(0)
	assert_false(v.needs_calibration, "a calibrated device")
	v.native.fake_remove_device("usb-1")
	v.native.fake_add_device("bt-2", "Bluetooth headset", true)
	v.tick(16667)
	v.tick(16667 + int(Tuning.f(&"voice.device_poll_s") * 1000000.0))
	assert_eq(v.native.device_id(), "bt-2")
	assert_true(v.needs_calibration, "a new device id repeats the line")


func test_bands_and_push_to_talk() -> void:
	var b: VoiceBands = VoiceBands.new()
	for i: int in 10:
		b.push(frame(-30.0, i))
	assert_eq(b.band, VoiceBands.Band.TALK)
	assert_true(b.sending(), "voice activation: open above silent")
	b.push_to_talk = true
	assert_false(b.sending(), "push-to-talk released: nothing goes out")
	assert_eq(b.band, VoiceBands.Band.TALK, "but the band is still measured")
	b.ptt_held = true
	assert_true(b.sending())
	b.reset()
	assert_eq(b.band, VoiceBands.Band.SILENT)
	assert_false(b.sending())
