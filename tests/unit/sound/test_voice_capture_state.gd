extends GutTest
## SND-05: the microphone's open and close rules on a fake device: Mute and the speech-impairment
## option never open it; it opens only while voice is live and closes on the tick voice stops; a
## device that vanishes stops frames and reads as no device within 1 s; one that returns opens again,
## flagging calibration when it is a different device; backend none forces Mute; frames are 20 ms
## of 48 kHz mono, stamped.

const POLL_USEC: int = 500000


func before_all() -> void:
	Tuning.load_client()


func _capture(mode: int = VoiceCapture.MicMode.USE) -> VoiceCapture:
	var v: VoiceCapture = VoiceCapture.new("fake")
	v.tap_far_end = false
	v.native.fake_add_device("usb-1", "USB headset", true)
	v.mic_mode = func() -> int: return mode
	return v


func test_mute_and_speech_impairment_never_open_the_device() -> void:
	var before: int = LbVoiceCapture.total_open_count()
	for mode: int in [VoiceCapture.MicMode.MUTE, VoiceCapture.MicMode.SPEECH_IMPAIRMENT]:
		var v: VoiceCapture = _capture(mode)
		v.voice_live = true
		for t: int in 600:  # ten seconds of frames
			v.tick(t * 16667)
		assert_eq(v.state, VoiceCapture.State.CLOSED)
		assert_eq(v.native.open_count(), 0, "never opened")
	assert_eq(LbVoiceCapture.total_open_count(), before, "the process-wide open counter stayed put")


func test_the_default_mode_is_mute_until_snd10_offers_the_choice() -> void:
	var v: VoiceCapture = VoiceCapture.new("fake")
	v.tap_far_end = false
	v.native.fake_add_device("usb-1", "USB headset", true)
	v.voice_live = true
	v.tick(0)
	assert_eq(v.native.open_count(), 0)


func test_opens_only_while_voice_is_live_and_closes_on_the_tick_it_stops() -> void:
	var v: VoiceCapture = _capture()
	v.tick(0)
	assert_eq(v.state, VoiceCapture.State.CLOSED, "not live: closed")
	v.voice_live = true
	v.tick(16667)
	assert_eq(v.state, VoiceCapture.State.OPEN)
	assert_true(v.native.is_open())
	v.voice_live = false
	v.tick(33333)
	assert_eq(v.state, VoiceCapture.State.CLOSED, "closed on the same tick, well inside 1 s")
	assert_false(v.native.is_open())
	assert_eq(v.native.open_count(), 1)


func test_switching_to_mute_closes_at_once() -> void:
	var mode: Dictionary = {"m": VoiceCapture.MicMode.USE}
	var v: VoiceCapture = VoiceCapture.new("fake")
	v.tap_far_end = false
	v.native.fake_add_device("usb-1", "USB headset", true)
	v.mic_mode = func() -> int: return int(Variants.number(mode["m"]))
	v.voice_live = true
	v.tick(0)
	assert_true(v.native.is_open())
	mode["m"] = VoiceCapture.MicMode.MUTE
	v.tick(16667)
	assert_false(v.native.is_open())


func test_frames_are_20_ms_of_48_khz_mono_and_stamped() -> void:
	var v: VoiceCapture = _capture()
	v.voice_live = true
	v.tick(0)
	var got: Array = []
	v.frame_ready.connect(func(pcm: PackedFloat32Array, t: int) -> void: got.append([pcm.size(), t]))
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(960 * 3)
	assert_true(v.native.fake_feed(samples))
	var now: int = Time.get_ticks_usec()
	v.tick(16667)
	assert_eq(got.size(), 3, "60 ms in, three frames out")
	for item: Array in got:
		var size: int = int(Variants.number(item[0]))
		var stamp: int = int(Variants.number(item[1]))
		assert_eq(size, 960)
		assert_almost_eq(float(stamp), float(now), 200000.0, "stamped on Time's clock")


func test_an_unplugged_device_reads_as_no_device_and_stops_frames() -> void:
	var v: VoiceCapture = _capture()
	v.voice_live = true
	v.tick(0)
	v.mark_calibrated()
	var got: Array = []
	v.frame_ready.connect(func(_pcm: PackedFloat32Array, _t: int) -> void: got.append(1))
	v.native.fake_remove_device("usb-1")
	v.tick(16667)
	assert_eq(v.state, VoiceCapture.State.NO_DEVICE, "no device on the next tick, well inside 1 s")
	assert_true(v.no_device(), "SND-10's label shows")
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(960)
	assert_false(v.native.fake_feed(samples), "nothing captured")
	v.tick(33333)
	assert_eq(got.size(), 0, "reads as silent")
	# The same device back: open again within a poll, no calibration needed.
	v.native.fake_add_device("usb-1", "USB headset", true)
	v.tick(16667 + POLL_USEC)
	assert_eq(v.state, VoiceCapture.State.OPEN)
	assert_false(v.needs_calibration, "the calibrated device came back")


func test_a_different_device_needs_calibration() -> void:
	var v: VoiceCapture = _capture()
	v.voice_live = true
	v.tick(0)
	v.mark_calibrated()
	v.native.fake_remove_device("usb-1")
	v.tick(16667)
	v.tick(16667 + POLL_USEC)
	assert_eq(v.state, VoiceCapture.State.NO_DEVICE, "nothing plugged in yet")
	v.native.fake_add_device("bt-2", "Bluetooth headset", true)
	v.tick(16667 + 2 * POLL_USEC)
	assert_eq(v.state, VoiceCapture.State.OPEN, "the replacement opens within a poll")
	assert_eq(v.native.device_id(), "bt-2")
	assert_true(v.needs_calibration, "a different device repeats the calibration line (SND-06)")


func test_the_poll_is_inside_one_second() -> void:
	assert_lt(Tuning.f(&"voice.device_poll_s"), 1.0)


func test_backend_none_forces_mute() -> void:
	var v: VoiceCapture = _capture()
	v.backend = "none"
	v.voice_live = true
	v.tick(0)
	assert_eq(v.effective_mode(), VoiceCapture.MicMode.MUTE)
	assert_eq(v.native.open_count(), 0)


func test_the_wanted_backend_starts() -> void:
	var v: VoiceCapture = _capture()
	assert_eq(v.backend, Tuning.s(&"voice.apm_backend"), "webrtc starts; no fallback needed")
	assert_true(v.native.configure("speex", "high", 100.0, PackedFloat32Array([-10, -15, -22, -30])), "speex starts")
	assert_true(v.native.configure("none", "low", 100.0, PackedFloat32Array([-10, -15, -22, -30])))
	assert_false(v.native.configure("rnnoise", "low", 100.0, PackedFloat32Array([-10, -15, -22, -30])), "unknown backend")
	assert_false(v.native.configure("webrtc", "max", 100.0, PackedFloat32Array([-10, -15, -22, -30])), "unknown level")


func test_the_far_end_tap_comes_and_goes_with_the_device() -> void:
	AudioBuses.install()
	var master: int = AudioServer.get_bus_index("Master")
	var effects: int = AudioServer.get_bus_effect_count(master)
	var v: VoiceCapture = _capture()
	v.tap_far_end = true
	v.voice_live = true
	v.tick(0)
	assert_eq(AudioServer.get_bus_effect_count(master), effects + 1, "the final mix tapped while open")
	v.tick(16667)
	v.voice_live = false
	v.tick(33333)
	assert_eq(AudioServer.get_bus_effect_count(master), effects, "and untapped when closed")
