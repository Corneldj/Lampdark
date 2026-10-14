extends "res://tests/scenario/kit/scenario_test.gd"
## SND-15 (Gameplay §6.8, §11.2, §9.2, A.3): after every fall, voice.knock_delay_s on, every
## conscious miner but the fallen gets exactly one empty KNOCKS message, wherever they are (60
## tiles off, behind shut gates, in a Fan surge); the fallen, the unconscious and the dead get none;
## nothing enters the Road Graph and no creature hears them; fall_heard fires once per hearer. After
## the cut the fallen's voice reaches nobody and makes no band events, phone lines included, until a
## revive. An unconscious miner shot dead makes no second set; an illusion never sends knocks.

const A = preload("res://tests/unit/sound/audio_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


## A long gallery with a shut gate near its far end: Ann falls at a; b is 5 tiles off; c 60 tiles
## off; d and e behind the gate.
func _mine() -> FixtureMap:
	var row: String = "#a....b" + ".".repeat(56) + "c" + "...G..d.e.#"
	return FixtureMap.from_ascii(PackedStringArray(["#".repeat(row.length()), row, "#".repeat(row.length())]))


func _crew(seed_value: int) -> Array:
	var s: Scenario = make({"seed": seed_value, "fixture": _mine()})
	var hs: Array[MinerHandle] = []
	for spot: String in ["a", "b", "c", "d", "e"]:
		hs.append(s.add_miner("m_" + spot, s.fixture.spot(spot)))
	s.step(3)
	return [s, hs]


func _knocks(h: MinerHandle) -> int:
	return h.connection.knocks


func test_every_conscious_miner_gets_one_set_per_fall() -> void:
	var p: Array = _crew(160)
	var s: Scenario = p[0]
	var hs: Array[MinerHandle] = p[1]
	var ann: MinerHandle = hs[0]
	assert_gte(s.fixture.spot("c").x - s.fixture.spot("a").x, 60, "a miner 60 tiles and more away")
	s.run.voice.conditions.fan_surge_active = true  # SND-16's stub: the Fan never masks them
	var creature_heard: Array = []
	s.run.noise.set_creature_listener(7001, s.fixture.spot("b"), 4.0)
	s.run.noise.creature_hooks.append(func(e: NoiseSystem.Event, _d: Dictionary) -> void: creature_heard.append(e.type))
	var heard: Array = []
	s.run.fall_audio.fall_heard.connect(func(miner: int, fall_id: int) -> void: heard.append([miner, fall_id]))
	var events_before: int = s.run.noise.event_log.size()
	var records: Array[Array] = A.capture(s)
	assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.MOTH_SMOTHER))
	var fell_at: int = s.run.tick
	var delay: int = roundi(Tuning.f(&"voice.knock_delay_s") * 20.0)
	s.step(delay - 1)
	for h: MinerHandle in hs:
		assert_eq(_knocks(h), 0, "not before %.1f s" % Tuning.f(&"voice.knock_delay_s"))
	s.step(4)
	assert_eq(_knocks(ann), 0, "never the fallen")
	for i: int in range(1, 5):
		assert_eq(_knocks(hs[i]), 1, "%s: one set, wherever they are" % hs[i].name)
	assert_eq(heard.size(), 4, "fall_heard once per conscious miner")
	var fall_id: int = int(Variants.number(heard[0][1]))
	for h: Array in heard:
		assert_eq(int(Variants.number(h[1])), fall_id)
	var types: Array = []
	for e: NoiseSystem.Event in s.run.noise.event_log.slice(events_before):
		types.append(e.type)
	assert_eq(types, [NoiseTypes.Type.FALL_SCREAM], "the scream is the fall's only Road Graph event: no knocks in it")
	assert_false(creature_heard.has(NoiseTypes.Type.NONE))
	assert_lte(creature_heard.size(), 1, "a creature hears the scream at most, never the knocks")
	assert_gte(s.run.tick - fell_at, delay)
	var screamed_at: Array = []
	for pair: Array in records:
		var r: AudioRecord = pair[1]
		if r.type == NoiseTypes.Type.FALL_SCREAM:
			screamed_at.append(pair[0])
	assert_eq(screamed_at, [hs[1].slot], "the scream reaches the miner 5 tiles off; behind the gate and 60 tiles off, only the knocks")


func test_the_fallen_unconscious_and_dead_get_none() -> void:
	var p: Array = _crew(161)
	var s: Scenario = p[0]
	var hs: Array[MinerHandle] = p[1]
	assert_true(s.run.falls.fall_unconscious(s.run, hs[1].entity_id, FallCause.Cause.BLAST))
	s.run.miner_state.kill(hs[2].entity_id, "test")
	s.step(60)
	for h: MinerHandle in hs:
		h.connection.knocks = 0
	assert_true(s.run.falls.fall_unconscious(s.run, hs[0].entity_id, FallCause.Cause.PIN))
	s.step(40)
	assert_eq([_knocks(hs[0]), _knocks(hs[1]), _knocks(hs[2]), _knocks(hs[3]), _knocks(hs[4])], [0, 0, 0, 1, 1],
		"the fallen, an unconscious miner and a dead one: none")


func test_two_falls_two_sets_and_a_death_while_down_none() -> void:
	var p: Array = _crew(162)
	var s: Scenario = p[0]
	var hs: Array[MinerHandle] = p[1]
	assert_true(s.run.falls.fall_unconscious(s.run, hs[0].entity_id, FallCause.Cause.MOTH_SMOTHER))
	s.step(2)
	assert_true(s.run.falls.fall_unconscious(s.run, hs[1].entity_id, FallCause.Cause.ROOF_FALL))
	s.step(40)
	assert_eq(_knocks(hs[4]), 2, "two falls, two sets")
	s.run.miner_state.kill(hs[0].entity_id, "shot_dead")  # already down: no new fall
	s.step(40)
	assert_eq(_knocks(hs[4]), 2, "an unconscious miner shot dead: no second knocks")
	s.run.miner_state.kill(hs[2].entity_id, "shot_dead")  # conscious, shot dead: a fall, no scream
	s.step(40)
	assert_eq(_knocks(hs[4]), 3, "a death from a conscious state knocks too")


func test_the_record_has_no_fields() -> void:
	assert_eq(Protocol.Msg.KNOCKS, 20)
	var framed: PackedByteArray = Protocol.frame(Protocol.Msg.KNOCKS, PackedByteArray())
	var m: Dictionary = Protocol.unframe(framed)
	assert_eq(int(Variants.number(m["type"])), Protocol.Msg.KNOCKS)
	var payload: PackedByteArray = m["payload"]
	assert_eq(payload.size(), 0, "no position, no id, no cause, no count")


func test_after_the_cut_the_voice_reaches_nobody_until_a_revive() -> void:
	var s: Scenario = make({"seed": 163, "fixture": A.hall()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(5, 3))
	var ben: MinerHandle = s.add_miner("ben", Vector2i(8, 3))
	var cat: MinerHandle = s.add_miner("cat", Vector2i(28, 3))
	s.step(3)
	s.run.voice.open_direct(ann.slot, cat.slot)
	assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.BLACKDAMP))
	s.step(40)
	assert_eq(int(Variants.number(s.run.voice.route_of[ann.slot])), VoiceRoutes.Route.CUT)
	ben.connection.voice_in.clear()
	cat.connection.voice_in.clear()
	var start: int = s.run.tick
	ann.at(start).say(3, 10)
	s.step(12)
	assert_eq(ben.connection.voice_in.size() + cat.connection.voice_in.size(), 0, "nobody, the phone line included")
	var events: int = 0
	for e: NoiseSystem.Event in s.run.noise.event_log:
		if e.type == NoiseTypes.Type.VOICE and e.tick >= start:
			events += 1
	assert_eq(events, 0, "no band events")
	s.run.miner_state.revive(ann.entity_id, &"kit")
	s.step(2)
	ann.at(s.run.tick).say(2, 6)
	s.step(8)
	assert_gt(ben.connection.voice_in.size(), 0, "revived: her voice is back")


func test_an_illusion_scream_never_sends_knocks() -> void:
	var p: Array = _crew(164)
	var s: Scenario = p[0]
	var hs: Array[MinerHandle] = p[1]
	# CRT-10's stub: an illusion scream is a record to one target, never a fall.
	var r: AudioRecord = AudioRecord.new()
	r.type = NoiseTypes.Type.FALL_SCREAM
	r.voice = 2
	r.start_tick = s.run.tick
	s.run.audio.deliver(hs[1].slot, r)
	s.step(60)
	for h: MinerHandle in hs:
		assert_eq(_knocks(h), 0, "a scream from the rock is no fall")
