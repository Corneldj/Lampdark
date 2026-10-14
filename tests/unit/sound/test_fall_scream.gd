extends "res://tests/scenario/kit/scenario_test.gd"
## SND-15 (Gameplay §6.8, A.3; GDD §15.5): a fall while talking carries the fallen's own voice at
## shout range for 1.5 s with no drops; with no voice on the mic their character screams to the
## listeners a shout reaches; a drag victim screams muffled at whisper range; the rock hears one
## 28 np scream per screaming fall and none for a revolver hit or a Hand.

const A = preload("res://tests/unit/sound/audio_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _corridor(w: int = 40) -> FixtureMap:
	return FixtureMap.from_ascii(PackedStringArray(["#".repeat(w + 2), "#a" + ".".repeat(w - 1) + "#", "#".repeat(w + 2)]))


## Ann at `a`, and a listener at each offset east.
func _line(seed_value: int, offsets: Array[int]) -> Array:
	var s: Scenario = make({"seed": seed_value, "fixture": _corridor()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var out: Array[MinerHandle] = []
	var i: int = 0
	for d: int in offsets:
		out.append(s.add_miner("l%d" % i, a + Vector2i(d, 0)))
		i += 1
	s.step(3)
	return [s, ann, out]


func _scream_events(s: Scenario) -> Array:
	var out: Array = []
	for e: NoiseSystem.Event in s.run.noise.event_log:
		if e.type == NoiseTypes.Type.FALL_SCREAM:
			out.append(e.level_np)
	return out


func _fall(s: Scenario, h: MinerHandle, cause: FallCause.Cause) -> void:
	assert_true(s.run.falls.fall_unconscious(s.run, h.entity_id, cause))


func test_a_fall_while_talking_carries_the_voice_at_shout_range() -> void:
	var p: Array = _line(150, [24, 25])
	var s: Scenario = p[0]
	var ann: MinerHandle = p[1]
	var near: MinerHandle = p[2][0]
	var far: MinerHandle = p[2][1]
	ann.at(s.run.tick).say(1, 200)  # a whisper: 3 tiles, until she falls
	s.step(5)
	assert_eq(near.connection.voice_in.size(), 0, "a whisper never reaches 24 tiles")
	_fall(s, ann, FallCause.Cause.MOTH_SMOTHER)
	s.step(1)
	assert_eq(int(Variants.number(s.run.voice.route_of[ann.slot])), VoiceRoutes.Route.FALL_SCREAM)
	near.connection.voice_in.clear()
	var scream_ticks: int = roundi(Tuning.f(&"voice.fall_scream_s") * 20.0)
	s.step(scream_ticks - 2)
	var got: int = near.connection.voice_in.size()
	assert_between(got, scream_ticks - 4, scream_ticks, "every frame for 1.5 s at 24 tiles: no drops (%d)" % got)
	for raw: Array in near.connection.voice_in:
		var packet: PackedByteArray = raw[0]
		assert_eq(int(Variants.number(VoicePackets.read_down(packet)["band"])), 1, "the band is still hers")
	assert_eq(far.connection.voice_in.size(), 0, "25 tiles: beyond a shout")
	s.step(4)
	assert_eq(int(Variants.number(s.run.voice.route_of[ann.slot])), VoiceRoutes.Route.CUT, "then the cut")
	near.connection.voice_in.clear()
	s.step(20)
	assert_eq(near.connection.voice_in.size(), 0, "after the cut nobody hears her")
	assert_eq(_scream_events(s), [28.0], "the rock: one 28 np scream")


func test_no_voice_on_the_mic_the_character_screams() -> void:
	for how: String in ["silence", "stopped talking"]:
		var p: Array = _line(151, [24, 25])
		var s: Scenario = p[0]
		var ann: MinerHandle = p[1]
		var got: Array[Array] = A.capture(s)
		if how == "stopped talking":
			ann.at(s.run.tick).say(2, 4)
			s.step(8)  # 4 ticks of silence since: over 100 ms
		_fall(s, ann, FallCause.Cause.ROOF_FALL)
		s.step(2)
		var by_slot: Dictionary = {}
		for pair: Array in got:
			var r: AudioRecord = pair[1]
			if r.type == NoiseTypes.Type.FALL_SCREAM:
				by_slot[pair[0]] = r
		var near: MinerHandle = p[2][0]
		var far: MinerHandle = p[2][1]
		assert_true(by_slot.has(near.slot), "%s: the character scream reaches 24 tiles" % how)
		assert_false(by_slot.has(far.slot), "%s: not 25" % how)
		if by_slot.has(near.slot):
			var r: AudioRecord = by_slot[near.slot]
			assert_between(r.voice, 0, 7, "in the fallen's character voice")
			assert_eq(r.flags & AudioRecord.MUFFLED, 0)
		assert_eq(_scream_events(s).size(), 1)


func test_a_drag_fall_screams_muffled_at_whisper_range() -> void:
	var p: Array = _line(152, [3, 4])
	var s: Scenario = p[0]
	var ann: MinerHandle = p[1]
	var got: Array[Array] = A.capture(s)
	_fall(s, ann, FallCause.Cause.DRAG)
	s.step(2)
	var heard: Dictionary = {}
	for pair: Array in got:
		var r: AudioRecord = pair[1]
		if r.type == NoiseTypes.Type.FALL_SCREAM:
			heard[pair[0]] = r
			assert_ne(r.flags & AudioRecord.MUFFLED, 0, "muffled")
	var three: MinerHandle = p[2][0]
	var four: MinerHandle = p[2][1]
	assert_true(heard.has(three.slot), "3 tiles: heard")
	assert_false(heard.has(four.slot), "4 tiles: not")
	assert_eq(int(Variants.number(s.run.voice.route_of[ann.slot])), VoiceRoutes.Route.FALL_MUFFLED)
	assert_eq(_scream_events(s), [28.0], "the rock still hears the scream")
	# Live: her own voice, muffled, to 3 tiles only.
	var q: Array = _line(153, [3, 4])
	var t: Scenario = q[0]
	var bea: MinerHandle = q[1]
	bea.at(t.run.tick).say(3, 100)
	t.step(4)
	_fall(t, bea, FallCause.Cause.DRAG)
	t.step(1)
	var near: MinerHandle = q[2][0]
	var far: MinerHandle = q[2][1]
	near.connection.voice_in.clear()
	far.connection.voice_in.clear()
	t.step(10)
	assert_gt(near.connection.voice_in.size(), 0)
	for raw: Array in near.connection.voice_in:
		var packet: PackedByteArray = raw[0]
		assert_true(Variants.flag(VoicePackets.read_down(packet)["muffled"]), "muffled")
	assert_eq(far.connection.voice_in.size(), 0, "a shout cut to a whisper: 4 tiles hears nothing")


func test_no_scream_for_a_revolver_hit_or_a_hand() -> void:
	for who: String in ["revolver", "hand", "shot dead"]:
		var p: Array = _line(154, [5])
		var s: Scenario = p[0]
		var ann: MinerHandle = p[1]
		var got: Array[Array] = A.capture(s)
		match who:
			"revolver":
				_fall(s, ann, FallCause.Cause.FRIENDLY_HIT)
			"hand":
				s.run.crew.is_hand_driven = func(entity: int) -> bool: return entity == ann.entity_id
				_fall(s, ann, FallCause.Cause.MOTH_SMOTHER)
			"shot dead":
				s.run.miner_state.kill(ann.entity_id, "shot_dead")
		s.step(2)
		assert_eq(_scream_events(s).size(), 0, "%s: no scream into the rock" % who)
		for pair: Array in got:
			var r: AudioRecord = pair[1]
			assert_ne(r.type, NoiseTypes.Type.FALL_SCREAM, "%s: no character scream" % who)
		assert_eq(int(Variants.number(s.run.voice.route_of[ann.slot])), VoiceRoutes.Route.CUT, "%s: cut at once" % who)
