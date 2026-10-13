extends GutTest
## SND-03 (client): gain from the level that arrived (no added distance cue), the buses by flag, the
## tell volume scaling only delivered tells, the voice cap stealing the quietest, playback only from
## the record's own position, and a real record and an illusion with the same bytes played and
## captioned identically.


func before_all() -> void:
	assert_true(Tuning.load_server())
	AudioBuses.install()


func _record(remaining: float, level: float, flags: int = 0) -> AudioRecord:
	var r: AudioRecord = AudioRecord.new()
	r.type = NoiseTypes.Type.SHOT
	r.apparent = Vector2(7.5, 3.5)
	r.level_np = level
	r.remaining_np = remaining
	r.flags = flags
	return r


func test_gain_from_remaining_level() -> void:
	var edge: float = Tuning.f(&"noise.playback_edge_attenuation_db")
	assert_almost_eq(EventPlayer.gain_db(_record(40.0, 40.0)), 0.0, 1e-6, "at the source: full")
	assert_almost_eq(EventPlayer.gain_db(_record(20.0, 40.0)), -edge * 0.5, 1e-6, "half the level left")
	assert_almost_eq(EventPlayer.gain_db(_record(0.0, 40.0)), -edge, 1e-6, "at the edge")
	var masked: AudioRecord = _record(40.0, 40.0)
	masked.gain_db = -12
	assert_almost_eq(EventPlayer.gain_db(masked), -12.0, 1e-6, "plus the masks' gain")
	assert_almost_eq(EventPlayer.gain_db(_record(0.0, 0.0, AudioRecord.DIFFUSE)), 0.0, 1e-6, "a tell: full delivered level")


func test_buses_by_flag() -> void:
	assert_eq(EventPlayer.bus_for(_record(1, 2)), "Game")
	assert_eq(EventPlayer.bus_for(_record(1, 2, AudioRecord.MUFFLED)), "Muffled")
	assert_eq(EventPlayer.bus_for(_record(1, 2, AudioRecord.DIFFUSE)), "Tells")
	assert_eq(EventPlayer.bus_for(_record(1, 2, AudioRecord.LOCAL)), "Ambience")
	var lp: AudioEffect = AudioServer.get_bus_effect(AudioServer.get_bus_index("Muffled"), 0)
	assert_true(lp is AudioEffectLowPassFilter, "Muffled low-passes")
	assert_almost_eq((lp as AudioEffectLowPassFilter).cutoff_hz, Tuning.f(&"noise.muffle_lowpass_hz"), 1e-3)


func test_plays_from_the_record_only() -> void:
	var p: EventPlayer = EventPlayer.new()
	add_child_autofree(p)
	p.listener = Vector2(2, 2)
	p.play(_record(30.0, 40.0), 1)
	assert_eq(p.voices.size(), 1)
	var at: Vector2 = p.voices[0][2]
	assert_eq(at, Vector2(7.5, 3.5), "from its apparent position, nothing derived")
	var id: int = p.voices[0][0]
	assert_true(p.mixer.has(id), "a source in the native mixer")


func test_tell_volume_scales_delivered_tells_only() -> void:
	var p: EventPlayer = EventPlayer.new()
	add_child_autofree(p)
	AudioBuses.set_tell_volume_db(6.0)
	var tells: int = AudioServer.get_bus_index("Tells")
	assert_almost_eq(AudioServer.get_bus_volume_db(tells), 6.0, 1e-6, "+6 dB on the Tells bus")
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Game")), 0.0, 1e-6, "nothing else")
	assert_eq(p.voices.size(), 0, "nothing delivered: nothing plays")
	AudioBuses.set_tell_volume_db(12.0)
	assert_almost_eq(AudioServer.get_bus_volume_db(tells), 6.0, 1e-6, "clamped to +6")
	AudioBuses.set_tell_volume_db(0.0)


func test_voice_cap_steals_the_quietest() -> void:
	var p: EventPlayer = EventPlayer.new()
	add_child_autofree(p)
	var cap: int = Tuning.i(&"noise.max_event_voices")
	p.play(_record(1.0, 40.0), 0)
	for i: int in cap:
		p.play(_record(30.0, 40.0), i + 1)
	assert_eq(p.voices.size(), cap)
	for v: Array in p.voices:
		assert_gt(float(Variants.number(v[1])), -20.0, "the quietest (1 np of 40) was stolen")
	assert_eq(p.mixer.native.count(), cap, "and its source left the mixer")


func test_real_and_illusion_identical() -> void:
	var a: EventPlayer = EventPlayer.new()
	var b: EventPlayer = EventPlayer.new()
	add_child_autofree(a)
	add_child_autofree(b)
	var caps: Array = []
	a.caption.connect(func(t: int, d: Variant) -> void: caps.append(["a", t, d]))
	b.caption.connect(func(t: int, d: Variant) -> void: caps.append(["b", t, d]))
	var real: AudioRecord = _record(25.0, 40.0)
	var illusion: AudioRecord = AudioRecord.from_event(real.to_event())
	a.play(real, 5)
	b.play(illusion, 5)
	var va: Array = a.voices[0]
	var vb: Array = b.voices[0]
	assert_eq(va.slice(1), vb.slice(1), "the same gain, position, bus, pitch and sample")
	var ca: Array = caps[0]
	var cb: Array = caps[1]
	assert_eq(ca.slice(1), cb.slice(1), "the same caption")


func test_sputter_voices_follow_guttering_flames() -> void:
	var p: EventPlayer = EventPlayer.new()
	add_child_autofree(p)
	p.set_sputters([Vector2(3, 3), Vector2(8, 1)] as Array[Vector2])
	assert_eq(p.sputter_voices.size(), 2, "one per guttering flame")
	assert_eq(p.sputter_at, [Vector2(3, 3), Vector2(8, 1)] as Array[Vector2], "at the flames")
	assert_eq(p.mixer.native.count(), 2, "looping sources in the mixer")
	p.set_sputters([] as Array[Vector2])
	assert_eq(p.sputter_voices.size(), 0, "the gutter ends: silence")
	assert_eq(p.mixer.native.count(), 0)
