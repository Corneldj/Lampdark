extends GutTest
## SND-04: headphones, speakers and mono each place a source by its azimuth off the facing and dull it
## behind; the output-mode setting defaults to headphones on PC (recommended at first launch) and
## speakers on a Steam Deck until the player chooses; mono comes with direction-only arcs; screen-up
## exists only where the debug tools do.

const NORTH: int = 49152
const PATH: String = "user://test_audio_options.cfg"


func before_all() -> void:
	assert_true(Tuning.load_server())
	AudioBuses.install()


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


## Left and right RMS of broadband noise at `at`, heard from (0, 0) facing north.
func _hear(mode: SpatialMixer.Mode, at: Vector2) -> Vector2:
	var m: SpatialMixer = SpatialMixer.new()
	autofree(m)
	m.set_mode(mode)
	m.set_pose(Vector2.ZERO, NORTH)
	var tone: PackedFloat32Array = PackedFloat32Array()
	tone.resize(22050)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	for i: int in tone.size():
		tone[i] = rng.randf_range(-0.4, 0.4)
	m.add(tone, 22050.0, at, 0.0, "Game")
	var out: PackedVector2Array = m.native.mix(0, 8192)
	var e: Vector2 = Vector2.ZERO
	for f: int in range(2048, 8192):
		e += Vector2(out[f].x * out[f].x, out[f].y * out[f].y)
	return Vector2(sqrt(e.x / 6144.0), sqrt(e.y / 6144.0))


func test_each_mode_places_by_azimuth() -> void:
	var ahead: Vector2 = Vector2(0, -6)
	var right: Vector2 = Vector2(6, 0)
	for mode: SpatialMixer.Mode in [SpatialMixer.Mode.HEADPHONES, SpatialMixer.Mode.SPEAKERS, SpatialMixer.Mode.MONO]:
		var c: Vector2 = _hear(mode, ahead)
		assert_lt(absf(20.0 * log(c.x / c.y) / log(10.0)), 1.0, "mode %d: ahead is centred (within 1 dB)" % mode)
		var r: Vector2 = _hear(mode, right)
		if mode == SpatialMixer.Mode.MONO:
			assert_almost_eq(r.x, r.y, 1e-4, "mono: no side")
		else:
			assert_gt(r.y, r.x * 2.0, "mode %d: to the right is right" % mode)


func test_each_mode_dulls_what_is_behind() -> void:
	for mode: SpatialMixer.Mode in [SpatialMixer.Mode.HEADPHONES, SpatialMixer.Mode.SPEAKERS, SpatialMixer.Mode.MONO]:
		var m: SpatialMixer = SpatialMixer.new()
		autofree(m)
		m.set_mode(mode)
		m.set_pose(Vector2.ZERO, NORTH)
		var one: PackedFloat32Array = PackedFloat32Array([0.1, 0.1])
		var behind: int = m.add(one, 22050.0, Vector2(0, 6), 0.0, "Game")
		var ahead: int = m.add(one, 22050.0, Vector2(0, -6), 0.0, "Game")
		assert_almost_eq(m.native.rear_cutoff_of(behind), float(Tuning.i(&"noise.rear_lowpass_min_hz")), 1e-6, "mode %d: 2 kHz behind" % mode)
		assert_eq(m.native.rear_cutoff_of(ahead), 0.0, "mode %d: unfiltered ahead" % mode)


func test_defaults_and_first_launch() -> void:
	var pc: AudioOptions = AudioOptions.defaults(false)
	assert_eq(pc.output_mode, SpatialMixer.Mode.HEADPHONES, "PC: headphones")
	assert_true(pc.recommend_headphones(false), "recommended at first launch")
	var deck: AudioOptions = AudioOptions.defaults(true)
	assert_eq(deck.output_mode, SpatialMixer.Mode.SPEAKERS, "Steam Deck: speakers")
	assert_false(deck.recommend_headphones(true))
	assert_almost_eq(pc.ringing_volume_db, Tuning.f(&"noise.ringing_volume_db"), 1e-6)


func test_choice_persists_and_mono_brings_arcs() -> void:
	var o: AudioOptions = AudioOptions.defaults(true)
	o.choose_output(SpatialMixer.Mode.MONO)
	o.set_ringing_volume_db(-20.0)
	assert_almost_eq(o.ringing_volume_db, -12.0, 1e-6, "clamped to -12")
	assert_true(o.direction_only_arcs(), "mono: direction-only arcs")
	assert_eq(o.save_to(PATH), OK)
	var back: AudioOptions = AudioOptions.load_from(PATH, true)
	assert_eq(back.output_mode, SpatialMixer.Mode.MONO, "the player's choice beats the Deck default")
	assert_true(back.chosen)
	assert_false(back.recommend_headphones(false), "no recommendation once chosen")
	assert_almost_eq(back.ringing_volume_db, -12.0, 1e-6)
	var m: SpatialMixer = SpatialMixer.new()
	autofree(m)
	back.apply(m)
	assert_eq(m.mode(), SpatialMixer.Mode.MONO)
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Ringing")), -12.0, 1e-6)
	AudioBuses.set_ringing_volume_db(0.0)


func test_screen_up_only_with_debug_tools() -> void:
	var m: SpatialMixer = SpatialMixer.new()
	autofree(m)
	var debug: bool = Variants.flag(ClassDB.class_call_static(&"LbCoreInfo", &"has_debug_tools"))
	assert_eq(m.screen_up_available(), debug, "screen-up compiled in exactly where the debug tools are")
	var ears: MinerListener = MinerListener.new(m)
	assert_false(ears.set_mode("sideways"))
	if not debug:
		assert_false(ears.set_mode("screen_up"), "a release build refuses")
		return
	var one: PackedFloat32Array = PackedFloat32Array([0.1, 0.1])
	var id: int = m.add(one, 22050.0, Vector2(0, -6), 0.0, "Game")
	ears.follow(Vector2.ZERO, 0)
	assert_almost_eq(m.native.azimuth_of(id), -90.0, 1e-6, "facing east: north is left")
	assert_true(ears.set_mode("screen_up"))
	assert_almost_eq(m.native.azimuth_of(id), 0.0, 1e-6, "screen-up: north is ahead whatever the facing")
	assert_true(ears.set_mode("facing"))
	assert_almost_eq(m.native.azimuth_of(id), -90.0, 1e-6)


func test_headphones_render_through_steam_audio() -> void:
	var m: SpatialMixer = SpatialMixer.new()
	autofree(m)
	assert_true(m.native.has_hrtf(), "Steam Audio loaded from beside the core: %s" % m.native.hrtf_error())
	assert_eq(m.hrtf_name(), "steam_audio")
	var with: Vector2 = _hear(SpatialMixer.Mode.HEADPHONES, Vector2(6, 0))
	m.native.use_hrtf(false)
	assert_eq(m.hrtf_name(), "spherical_head", "the fallback when switched off (or missing)")
	assert_gt(with.y, with.x * 2.0, "the HRTF puts a source to the right on the right")
