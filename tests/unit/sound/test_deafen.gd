extends "res://tests/scenario/kit/scenario_test.gd"
## SND-04 (Gameplay §4.7, §7.6, A.3): while deafened, tells, rock taps, voices and callouts never
## arrive and every other game sound arrives noise.deafen_dip_db down, for noise.deafen_duration_s; a
## new shot restarts the timer. The client rings on the Ringing bus and dips its own beds; the ringing
## volume option (-12 to 0 dB) never changes the dip.

const A = preload("res://tests/unit/sound/audio_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())
	AudioBuses.install()


func _record(type: int, flags: int = 0) -> AudioRecord:
	var r: AudioRecord = AudioRecord.new()
	r.type = type
	r.flags = flags
	r.level_np = 10.0
	r.remaining_np = 8.0
	return r


func test_mask_drops_tells_taps_voices_and_dips_the_rest() -> void:
	var s: Scenario = make({"seed": 41, "fixture": A.hall()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(5, 3))
	var bob: MinerHandle = s.add_miner("bob", Vector2i(20, 3))
	s.step(2)
	var got: Array[Array] = A.capture(s)
	s.run.deafen.deafen(s.run, ann.slot)
	assert_true(s.run.deafen.is_deafened(ann.slot))
	assert_false(s.run.deafen.is_deafened(bob.slot))
	var dropped: Array[AudioRecord] = [_record(LocalSounds.Type.MOTH_STIR, AudioRecord.DIFFUSE), _record(NoiseTypes.Type.ROCK_TAP),
		_record(NoiseTypes.Type.VOICE), _record(NoiseTypes.Type.CALLOUT)]
	for r: AudioRecord in dropped:
		assert_false(s.run.audio.deliver(ann.slot, r), "%d never reaches the deafened" % r.type)
	assert_eq(got.size(), 0)
	var hammer: AudioRecord = _record(NoiseTypes.Type.HAMMER)
	assert_true(s.run.audio.deliver(ann.slot, hammer))
	assert_eq(hammer.gain_db, -roundi(Tuning.f(&"noise.deafen_dip_db")), "20 dB down")
	var tap: AudioRecord = _record(NoiseTypes.Type.ROCK_TAP)
	assert_true(s.run.audio.deliver(bob.slot, tap), "Bob is not deafened")
	assert_eq(tap.gain_db, 0)


func test_lasts_five_seconds_and_a_new_shot_restarts_it() -> void:
	var s: Scenario = make({"seed": 42, "fixture": A.hall()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(5, 3))
	s.step(2)
	var ticks: int = roundi(Tuning.f(&"noise.deafen_duration_s") * Tuning.f(&"net.tick_hz"))
	s.run.deafen.deafen(s.run, ann.slot)
	s.step(ticks - 20)
	assert_true(s.run.deafen.is_deafened(ann.slot), "still ringing a second before the end")
	s.run.deafen.deafen(s.run, ann.slot)
	s.step(ticks - 1)
	assert_true(s.run.deafen.is_deafened(ann.slot), "the second shot restarted the 5 s, not added to the first")
	s.step(1)
	assert_false(s.run.deafen.is_deafened(ann.slot), "5 s after the last shot it ends")
	var hammer: AudioRecord = _record(NoiseTypes.Type.HAMMER)
	assert_true(s.run.audio.deliver(ann.slot, hammer))
	assert_eq(hammer.gain_db, 0, "full level again")
	var records: int = 0
	for d: Dictionary in ann.connection.deafened:
		records += 1
		assert_almost_eq(float(Variants.number(d["duration_s"])), Tuning.f(&"noise.deafen_duration_s"), 1e-6)
		assert_almost_eq(float(Variants.number(d["dip_db"])), Tuning.f(&"noise.deafen_dip_db"), 1e-6)
	assert_eq(records, 2, "one Deafened record per shot, to Ann's client")


func test_state_round_trips() -> void:
	var d: Deafen = Deafen.new()
	d.until = {2: 140, 0: 90}
	var w: SimStateWriter = SimStateWriter.new()
	d.write_state(w)
	var back: Deafen = Deafen.new()
	back.read_state(SimStateReader.new(w.bytes()))
	assert_eq(back.until, {0: 90, 2: 140})


func test_message_round_trips() -> void:
	assert_eq(DeafenedMessages.decode(DeafenedMessages.encode(5.0, 20.0)), {"duration_s": 5.0, "dip_db": 20.0})
	assert_eq(DeafenedMessages.decode(PackedByteArray([1, 2])), {}, "malformed")


func test_client_rings_and_dips_its_beds() -> void:
	var beds: AmbientBeds = AmbientBeds.new()
	add_child_autofree(beds)
	var deaf: Deafness = Deafness.new(beds)
	add_child_autofree(deaf)
	deaf.set_process(false)
	var captions: Array[bool] = []
	deaf.ringing.connect(func(on: bool) -> void: captions.append(on))
	var bed: float = Tuning.f(&"noise.bed_volume_db")
	deaf.start({"duration_s": 5.0, "dip_db": 20.0})
	assert_eq(deaf.player.bus, "Ringing")
	assert_true(deaf.player.playing, "the ringing plays")
	for raw: Variant in beds.players.values():
		var p: AudioStreamPlayer = raw
		assert_almost_eq(p.volume_db, bed - 20.0, 1e-4, "the beds dip 20 dB")
	deaf.advance(4.0)
	deaf.start({"duration_s": 5.0, "dip_db": 20.0})
	deaf.advance(4.5)
	assert_true(deaf.deafened(), "a second record restarts the ringing")
	deaf.advance(0.5)
	assert_false(deaf.deafened())
	assert_null(deaf.player, "the ringing stops")
	for raw: Variant in beds.players.values():
		var p: AudioStreamPlayer = raw
		assert_almost_eq(p.volume_db, bed, 1e-4, "the beds come back")
	assert_eq(captions, [true, false] as Array[bool], "'[ringing]' once on, once off")


func test_ringing_volume_option_never_changes_the_dip() -> void:
	var ringing: int = AudioServer.get_bus_index("Ringing")
	var beds: AmbientBeds = AmbientBeds.new()
	add_child_autofree(beds)
	var deaf: Deafness = Deafness.new(beds)
	add_child_autofree(deaf)
	deaf.set_process(false)
	deaf.start({"duration_s": 5.0, "dip_db": 20.0})
	var dipped: Array[float] = []
	for db: float in [-12.0, -6.0, 0.0]:
		AudioBuses.set_ringing_volume_db(db)
		assert_almost_eq(AudioServer.get_bus_volume_db(ringing), db, 1e-6)
		var p: AudioStreamPlayer = beds.players.values()[0]
		dipped.append(p.volume_db)
	assert_eq(dipped[0], dipped[2], "the beds' dip is the same at any ringing volume")
	AudioBuses.set_ringing_volume_db(-30.0)
	assert_almost_eq(AudioServer.get_bus_volume_db(ringing), -12.0, 1e-6, "clamped to -12")
	AudioBuses.set_ringing_volume_db(6.0)
	assert_almost_eq(AudioServer.get_bus_volume_db(ringing), 0.0, 1e-6, "clamped to 0")
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Game")), 0.0, 1e-6, "Game untouched")
