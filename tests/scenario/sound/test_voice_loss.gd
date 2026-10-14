extends "res://tests/scenario/kit/scenario_test.gd"
## SND-08 end to end over the kit's network: each listener's rate as the server works it out
## (distance, the Stythe, running; combined), frames dropped in runs on the way, the Fan's and the
## shot's cuts, the band events untouched by any listener's loss, and independent listeners.


func before_all() -> void:
	assert_true(Tuning.load_server())


func _corridor() -> FixtureMap:
	return FixtureMap.from_ascii(PackedStringArray(["#".repeat(32), "#a" + ".".repeat(29) + "#", "#".repeat(32)]))


## The rates the server holds for a listener of `speaker`'s current utterance.
func _rates(s: Scenario, speaker: MinerHandle, listener: MinerHandle) -> Dictionary:
	var st: Dictionary = Variants.dict(s.run.voice._speaking.get(speaker.slot, {}))
	return Variants.dict(Variants.dict(st.get("rates", {})).get(listener.slot, {}))


func _count(h: MinerHandle) -> int:
	var n: int = h.connection.voice_in.size()
	h.connection.voice_in.clear()
	return n


func test_distance_rates_from_half_range_to_the_edge() -> void:
	var s: Scenario = make({"seed": 81, "fixture": _corridor()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var at6: MinerHandle = s.add_miner("ben", a + Vector2i(6, 0))
	var at9: MinerHandle = s.add_miner("cat", a + Vector2i(9, 0))
	var at12: MinerHandle = s.add_miner("dan", a + Vector2i(12, 0))
	s.step(3)
	ann.at(s.run.tick).say(2, 2)
	s.step(4)
	assert_almost_eq(float(Variants.number(_rates(s, ann, at6)["loss"])), 0.0, 1e-6, "talk at 6 tiles: clean")
	assert_almost_eq(float(Variants.number(_rates(s, ann, at9)["loss"])), 0.2, 1e-6, "at 9: 20%")
	assert_almost_eq(float(Variants.number(_rates(s, ann, at12)["loss"])), 0.4, 1e-6, "at 12, the edge: 40%")


func test_frames_drop_in_runs_on_the_way() -> void:
	var s: Scenario = make({"seed": 82, "fixture": _corridor()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var edge: MinerHandle = s.add_miner("ben", a + Vector2i(12, 0))
	s.step(3)
	edge.connection.voice_in.clear()
	var seqs: Array[int] = []
	s.on_tick = func(_sc: Scenario) -> void:
		for raw: Array in edge.connection.voice_in:
			var packet: PackedByteArray = raw[0]
			seqs.append(int(Variants.number(VoicePackets.read_down(packet)["seq"])))
		edge.connection.voice_in.clear()
	ann.at(s.run.tick).say(2, 1000)
	s.step(1003)
	s.on_tick = Callable()
	var kept: float = seqs.size() / 1000.0
	gut.p("at the edge: %.1f%% of 1,000 frames arrived" % [kept * 100.0])
	assert_between(kept, 0.52, 0.68, "about 60% kept at the edge (40% lost)")
	var gaps_ok: bool = true
	for i: int in range(1, seqs.size()):
		var gap: int = seqs[i] - seqs[i - 1] - 1
		if gap != 0 and (gap < 3 or gap > 10):
			gaps_ok = false
	assert_true(gaps_ok, "every gap is a run of 3-10 frames")


func test_the_edge_a_hunting_stythe_and_a_run_keep_about_a_third() -> void:
	var s: Scenario = make({"seed": 83, "fixture": _corridor()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a + Vector2i(14, 0))
	var edge: MinerHandle = s.add_miner("ben", a + Vector2i(26, 0))
	s.step(3)
	var stythe_at: Vector2 = s.run.registry.get_entity(ann.entity_id).position + Vector2(-2.0, 0.0)
	s.run.voice.conditions.stythe_tells = func() -> Array[Vector2]: return [stythe_at] as Array[Vector2]
	# Ann runs toward Ben, talking near the edge, the Stythe beside her: the edge, the Stythe, the run.
	ann.at(s.run.tick).say(2, 8).move(0.0, InputRecord.Gait.RUN, 8)
	s.step(5)
	var r: Dictionary = _rates(s, ann, edge)
	gut.p("rates: %s" % r)
	assert_gt(float(Variants.number(r["running_loss"])), 0.0, "running")
	assert_almost_eq(float(Variants.number(r["stythe_loss"])), 0.25, 1e-6, "the Stythe")
	var keep: float = 1.0 - float(Variants.number(r["loss"]))
	var expected: float = (1.0 - float(Variants.number(r["distance_loss"]))) * 0.75 * 0.8
	assert_almost_eq(keep, expected, 1e-6, "independent: the product of what each keeps")
	# Gameplay's worked example: at the edge exactly, 0.6 x 0.75 x 0.8 = 0.36.
	assert_almost_eq(LbVoiceLoss.combine(PackedFloat64Array([0.4, 0.25, 0.2])), 0.64, 1e-9)


func test_the_stythe_from_speaker_or_listener_only_adds_a_quarter_and_crackle() -> void:
	var s: Scenario = make({"seed": 84, "fixture": _corridor()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var ben: MinerHandle = s.add_miner("ben", a + Vector2i(5, 0))
	s.step(3)
	var ben_at: Vector2 = s.run.registry.get_entity(ben.entity_id).position
	var cases: Array = [[ben_at + Vector2(8.0, 0.0), 0.25, "within 10 tiles of the listener only"],
		[ben_at + Vector2(16.0, 0.0), 0.0, "beyond 10 tiles of both"]]
	for c: Array in cases:
		var at: Vector2 = c[0]
		s.run.voice.conditions.stythe_tells = func() -> Array[Vector2]: return [at] as Array[Vector2]
		ben.connection.voice_in.clear()
		ann.at(s.run.tick).say(2, 3)
		s.step(8)  # every frame delivered
		var r: Dictionary = _rates(s, ann, ben)
		assert_almost_eq(float(Variants.number(r["stythe_loss"])), float(Variants.number(c[1])), 1e-6, str(c[2]))
		var heard: bool = false
		for raw: Array in ben.connection.voice_in:
			var packet: PackedByteArray = raw[0]
			var d: Dictionary = VoicePackets.read_down(packet)
			if not Variants.flag(d["end"]):  # the last utterance's END, which carries no audio
				heard = heard or Variants.flag(d["crackle"])
		ben.connection.voice_in.clear()
		assert_eq(heard, float(Variants.number(c[1])) > 0.0, "crackle with it: %s" % c[2])
		s.run.voice.on_voice(ann.slot, VoicePackets.end(9999))  # the utterance ends: the next is new


func test_the_fan_cuts_beyond_half_range_and_deafness_cuts_for_its_length() -> void:
	var s: Scenario = make({"seed": 85, "fixture": _corridor()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var near: MinerHandle = s.add_miner("ben", a + Vector2i(4, 0))
	var far: MinerHandle = s.add_miner("cat", a + Vector2i(9, 0))
	s.step(3)
	s.run.voice.conditions.fan_surge_active = true
	_count(near)
	_count(far)
	ann.at(s.run.tick).say(2, 5)
	s.step(8)
	assert_eq(_count(far), 0, "the Fan: nothing beyond half range")
	assert_eq(_count(near), 5, "within it, untouched by the Fan")
	s.run.voice.conditions.fan_surge_active = false
	s.run.deafen.deafen(s.run, near.slot, 5.0)
	ann.at(s.run.tick).say(2, 5)
	s.step(8)
	assert_eq(_count(near), 0, "deafened: nothing")
	s.step(roundi(5.0 * 20.0))
	ann.at(s.run.tick).say(2, 5)
	s.step(8)
	assert_eq(_count(near), 5, "after the 5 s, frames resume")


func test_the_rock_hears_every_band_whatever_a_listener_loses() -> void:
	var bands: Array = []
	for cut: bool in [false, true]:
		var s: Scenario = make({"seed": 86, "fixture": _corridor()})
		var a: Vector2i = s.fixture.spot("a")
		var ann: MinerHandle = s.add_miner("ann", a)
		var ben: MinerHandle = s.add_miner("ben", a + Vector2i(13, 0))  # only a shout reaches; past its half range
		s.step(3)
		var heard: Array = []
		s.run.voice.band_heard.connect(func(_slot: int, band: int) -> void: heard.append(band))
		s.run.voice.conditions.fan_surge_active = cut  # cut: Ben loses every frame
		ann.at(s.run.tick).say(1, 3).say(3, 4).say(2, 5)
		s.step(15)
		assert_eq(_count(ben) == 0, cut)
		bands.append(heard)
	var clean: Array = bands[0]
	var lossy: Array = bands[1]
	assert_eq(clean, lossy, "SND-09's band events are the same at 0% and 100% listener loss")
	assert_gt(clean.size(), 0)


func test_two_listeners_lose_independently() -> void:
	var s: Scenario = make({"seed": 87, "fixture": FixtureMap.from_ascii(PackedStringArray([
		"#".repeat(27), "#" + ".".repeat(12) + "a" + ".".repeat(12) + "#", "#".repeat(27)]))})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var east: MinerHandle = s.add_miner("ben", a + Vector2i(11, 0))
	var west: MinerHandle = s.add_miner("cat", a - Vector2i(11, 0))
	s.step(3)
	_count(east)
	_count(west)
	ann.at(s.run.tick).say(2, 400)
	s.step(403)
	var got: Array = []
	for h: MinerHandle in [east, west]:
		var seen: Dictionary = {}
		for raw: Array in h.connection.voice_in:
			var packet: PackedByteArray = raw[0]
			seen[int(Variants.number(VoicePackets.read_down(packet)["seq"]))] = true
		h.connection.voice_in.clear()
		got.append(seen)
	var e: Dictionary = got[0]
	var w: Dictionary = got[1]
	assert_ne(e.keys(), w.keys(), "the same distance, different frames lost")
	var both_lost: int = 0
	for seq: int in 400:
		if not e.has(seq) and not w.has(seq):
			both_lost += 1
	var p: float = float(Variants.number(_rates(s, ann, east)["loss"]))
	gut.p("each loses %.0f%%; both lost %d of 400 (independent: about %.0f)" % [p * 100.0, both_lost, p * p * 400.0])
	assert_between(both_lost / 400.0, p * p - 0.08, p * p + 0.08)


func test_nothing_tells_a_client_the_rates() -> void:
	var s: Scenario = make({"seed": 88, "fixture": _corridor()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var ben: MinerHandle = s.add_miner("ben", a + Vector2i(10, 0))
	s.step(3)
	ben.connection.voice_in.clear()
	ann.at(s.run.tick).say(2, 20)
	s.step(23)
	for raw: Array in ben.connection.voice_in:
		var packet: PackedByteArray = raw[0]
		var d: Dictionary = VoicePackets.read_down(packet)
		assert_false(d.has("loss") or d.has("rate") or d.has("condition"))
	assert_eq(VoicePackets.DOWN_HEADER, 15, "the header is the fixed 15 bytes: no rate or condition rides it")
	ben.connection.voice_in.clear()
