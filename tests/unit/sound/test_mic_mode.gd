extends GutTest
## SND-10: the mic modes, the label and the device-open gate. Mute until a choice is logged under
## the current notice; voice only in USE with a device; one label for Mute, the speech-impairment
## option and no device; SND-05's capture never opens the device unless voice is enabled.

var _dir: String = ""


func before_all() -> void:
	Tuning.load_client()


func before_each() -> void:
	_dir = "user://test_mic_mode_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)


func after_each() -> void:
	for f: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(f))
	DirAccess.remove_absolute(_dir)


func _mode(version: int = 1) -> MicMode:
	var v: String = _dir.path_join("version.json")
	var f: FileAccess = FileAccess.open(v, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": version}))
	f.close()
	return MicMode.new(_dir.path_join("log.jsonl"), _dir.path_join("queue.jsonl"), v)


func test_before_any_choice_the_mode_is_mute_and_the_screen_is_needed() -> void:
	var m: MicMode = _mode()
	assert_eq(m.mode, MicMode.Mode.MUTE)
	assert_true(m.needs_choice())
	assert_true(m.first_launch())
	assert_true(m.show_mute_label())
	assert_false(m.voice_enabled())


func test_voice_only_in_use_with_a_device() -> void:
	var m: MicMode = _mode()
	m.set_mode(MicMode.Mode.USE)
	assert_true(m.voice_enabled())
	assert_false(m.show_mute_label())
	m.set_device_present(false)
	assert_false(m.voice_enabled(), "no device")
	assert_true(m.show_mute_label(), "no device shows the label")
	m.set_device_present(true)
	assert_false(m.show_mute_label(), "the device returns in USE: the label goes")


func test_mute_and_speech_impairment_share_the_label() -> void:
	var m: MicMode = _mode()
	for mode: int in [MicMode.Mode.MUTE, MicMode.Mode.SPEECH_IMPAIRMENT]:
		m.set_mode(mode as MicMode.Mode)
		assert_true(m.show_mute_label())
		assert_false(m.voice_enabled())


func test_label_changes_are_signalled_for_the_server() -> void:
	var m: MicMode = _mode()
	var seen: Array = []
	m.label_changed.connect(func(muted: bool) -> void: seen.append(muted))
	m.set_mode(MicMode.Mode.USE)
	m.set_device_present(false)
	m.set_device_present(true)
	m.set_mode(MicMode.Mode.MUTE)
	assert_eq(seen, [false, true, false, true])


func test_the_device_open_gate_holds_for_mute_and_speech_impairment() -> void:
	var before: int = LbVoiceCapture.total_open_count()
	for mode: int in [MicMode.Mode.MUTE, MicMode.Mode.SPEECH_IMPAIRMENT]:
		var m: MicMode = _mode()
		m.set_mode(mode as MicMode.Mode)
		var v: VoiceCapture = VoiceCapture.new("fake")
		v.tap_far_end = false
		v.native.fake_add_device("usb-1", "USB headset", true)
		v.mic_mode = func() -> int: return m.mode
		v.voice_live = true
		for t: int in 300:
			v.tick(t * 16667)
		assert_eq(v.native.open_count(), 0)
	assert_eq(LbVoiceCapture.total_open_count(), before, "the device-open counter stays 0")
	var u: MicMode = _mode()
	u.set_mode(MicMode.Mode.USE)
	var w: VoiceCapture = VoiceCapture.new("fake")
	w.tap_far_end = false
	w.native.fake_add_device("usb-1", "USB headset", true)
	w.mic_mode = func() -> int: return u.mode
	w.voice_live = true
	w.tick(0)
	assert_eq(w.native.open_count(), 1, "USE opens it")


func test_entries_carry_no_audio() -> void:
	var m: MicMode = _mode()
	m.set_mode(MicMode.Mode.USE)
	var keys: Array = m.entries()[0].keys()
	keys.sort()
	assert_eq(keys, ["build", "choice", "notice_version", "utc"], "a choice, a version, a time, a build: nothing else")


## As the client wires them: the capture's state feeds the device presence, and the label follows.
func test_the_label_follows_an_unplug_and_a_replug_in_use_mode() -> void:
	var m: MicMode = _mode()
	m.set_mode(MicMode.Mode.USE)
	var v: VoiceCapture = VoiceCapture.new("fake")
	v.tap_far_end = false
	v.native.fake_add_device("usb-1", "USB headset", true)
	v.mic_mode = func() -> int: return m.mode
	v.state_changed.connect(func(_s: int) -> void: m.set_device_present(not v.no_device()))
	v.voice_live = true
	v.tick(0)
	assert_false(m.show_mute_label(), "voice enabled")
	v.native.fake_remove_device("usb-1")
	v.tick(16667)
	assert_true(m.show_mute_label(), "on at the next frame after the unplug, well inside 1 s")
	v.native.fake_add_device("usb-1", "USB headset", true)
	v.tick(16667 + int(Tuning.f(&"voice.device_poll_s") * 1000000.0))
	assert_false(m.show_mute_label(), "off when the device returns in USE mode")
