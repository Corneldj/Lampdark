extends "res://tests/scenario/kit/scenario_test.gd"
## SND-09 (Gameplay §6.2, §6.3, §7.3, A.3): every band a speaker sends is a Road Graph voice event
## at their miner, at band onset and every noise.voice_event_interval_s, at the band's np, by route;
## built before any listener's loss, so it is the same when listeners get nothing; heard by a
## creature listener (the Tapper's ring-1 hearing); never a record for any client.

const A = preload("res://tests/unit/sound/audio_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_each() -> void:
	super.after_each()
	WorldCoords.ring_override = -1


func _corridor() -> FixtureMap:
	return FixtureMap.from_ascii(PackedStringArray(["#".repeat(32), "#a" + ".".repeat(29) + "#", "#".repeat(32)]))


## [tick, np] of every voice event since `from` (the true-world event log).
func _voice_events(s: Scenario, from: int = 0) -> Array:
	var out: Array = []
	for e: NoiseSystem.Event in s.run.noise.event_log:
		if e.type == NoiseTypes.Type.VOICE and e.tick >= from:
			out.append([e.tick, e.level_np])
	return out


func test_each_band_at_onset_and_every_quarter_second() -> void:
	var nps: Array[float] = [0.0, 6.0, 12.0, 20.0, 28.0]
	for band: int in range(1, 5):
		var s: Scenario = make({"seed": 100 + band, "fixture": _corridor()})
		var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
		s.step(3)
		var start: int = s.run.tick
		ann.at(start).say(band, 11)  # 0.55 s: onset, +0.25 s, +0.5 s
		s.step(14)
		var got: Array = _voice_events(s, start)
		assert_eq(got.size(), 3, "band %d: onset and every 0.25 s" % band)
		var every: int = roundi(Tuning.f(&"noise.voice_event_interval_s") * Tuning.f(&"net.tick_hz"))
		for i: int in got.size():
			var ev: Array = got[i]
			assert_eq(float(Variants.number(ev[1])), nps[band], "band %d is %.0f np" % [band, nps[band]])
			if i > 0:
				var prev: Array = got[i - 1]
				assert_eq(int(Variants.number(ev[0])) - int(Variants.number(prev[0])), every)


func test_the_events_by_route() -> void:
	assert_eq(VoiceNoise.level_np(VoiceRoutes.Route.NORMAL, 3), 20.0)
	assert_eq(VoiceNoise.level_np(VoiceRoutes.Route.DRAGGED, 3), 20.0, "dragged: the true band; only forwarding is muffled")
	assert_eq(VoiceNoise.level_np(VoiceRoutes.Route.ASIDE, 4), 6.0, "the Aside: whisper np")
	assert_eq(VoiceNoise.level_np(VoiceRoutes.Route.COMING_ROUND, 2), 6.0, "coming round: whisper np")
	assert_eq(VoiceNoise.level_np(VoiceRoutes.Route.FALL_SCREAM, 4), 0.0, "SND-15 emits the fall's one scream")
	assert_eq(VoiceNoise.level_np(VoiceRoutes.Route.CUT, 2), 0.0)
	assert_eq(VoiceNoise.level_np(VoiceRoutes.Route.NORMAL, 0), 0.0, "silent: nothing")


func test_the_same_events_whatever_the_listeners_lose() -> void:
	var runs: Array = []
	for cut: bool in [false, true]:
		var s: Scenario = make({"seed": 110, "fixture": _corridor()})
		var a: Vector2i = s.fixture.spot("a")
		var ann: MinerHandle = s.add_miner("ann", a)
		var ben: MinerHandle = s.add_miner("ben", a + Vector2i(4, 0))
		s.step(3)
		if cut:
			s.run.deafen.deafen(s.run, ben.slot, 30.0)  # Ben gets no frame at all
		ben.connection.voice_in.clear()
		var start: int = s.run.tick
		ann.at(start).say(2, 8).wait(8).say(3, 6)
		s.step(20)
		assert_eq(ben.connection.voice_in.size() == 0, cut, "cut: every frame to Ben lost")
		var rel: Array = []
		for ev: Array in _voice_events(s, start):
			rel.append([int(Variants.number(ev[0])) - start, ev[1]])
		runs.append(rel)
	var clean: Array = runs[0]
	var lossy: Array = runs[1]
	assert_eq(clean, lossy, "the events are identical at 0% and 100% loss")
	assert_gt(Variants.array(runs[0]).size(), 0)


func test_a_ring_one_tapper_hears_talk_no_teammate_heard() -> void:
	WorldCoords.ring_override = 1
	var s: Scenario = make({"seed": 111, "fixture": _corridor()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var ben: MinerHandle = s.add_miner("ben", a + Vector2i(3, 0))
	s.step(3)
	var tapper_id: int = 9001
	var mult: float = CreatureTables.tapper_hearing_mult(1)
	s.run.noise.set_creature_listener(tapper_id, a + Vector2i(8, 0), mult)
	var heard: Array = []
	s.run.noise.creature_hooks.append(func(e: NoiseSystem.Event, d: Dictionary) -> void:
		if int(Variants.number(d["listener"])) == tapper_id and e.type == NoiseTypes.Type.VOICE:
			heard.append(e.level_np))
	s.run.deafen.deafen(s.run, ben.slot, 30.0)
	ann.at(s.run.tick).say(2, 10)
	s.step(12)
	ann.connection.send_voice(VoicePackets.end(ann.voice_frames_sent))
	s.step(2)
	assert_eq(s.run.heard.heard_log.size(), 0, "no teammate heard it (Ben is deafened)")
	assert_gt(heard.size(), 0, "the Tapper 8 tiles off in ring 1 heard the talk")
	assert_eq(float(Variants.number(heard[0])), 12.0)


func test_no_client_is_sent_a_band() -> void:
	var s: Scenario = make({"seed": 112, "fixture": A.hall()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(5, 3))
	s.add_miner("ben", Vector2i(9, 3))
	s.step(2)
	var got: Array[Array] = A.capture(s)
	ann.at(s.run.tick).say(3, 12)
	s.step(14)
	assert_gt(_voice_events(s).size(), 0)
	for pair: Array in got:
		var r: AudioRecord = pair[1]
		assert_ne(r.type, NoiseTypes.Type.VOICE, "a band event never becomes a record for any client")
	var msgs: PackedStringArray = PackedStringArray()
	for key: String in Protocol.Msg.keys():
		msgs.append(key)
	for word: String in ["HEARD", "UNHEARD", "BAND"]:
		for key: String in msgs:
			assert_false(key.contains(word), "no %s message: nothing tells a client" % key)


func test_the_dead_and_a_channel_make_no_noise() -> void:
	var s: Scenario = make({"seed": 113, "fixture": _corridor()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.step(3)
	s.run.voice.channel_join("dream", ann.slot)
	var start: int = s.run.tick
	ann.at(start).say(2, 6)
	s.step(8)
	assert_eq(_voice_events(s, start).size(), 0, "a channel replaces proximity: no event in the mine")
