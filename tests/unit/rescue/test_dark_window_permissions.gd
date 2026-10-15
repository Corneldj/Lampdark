extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-04: in a coming-round window the seen set holds only lit tiles within 4 tiles; an 8 s crawl
## moves at most 4 tiles and none while carried; 'Help!' is a 12 np event, speech reaches the living
## as muffled whisper-band voice with 6 np events. Outside a window nothing of the mine is seen.

const D = preload("res://tests/scenario/rescue/dark_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_sight_crawl_and_voice() -> void:
	var rows: PackedStringArray = ["##########################", "#........................#", "#..a.b...................#",
		"#........................#", "##########################"]
	var s: Scenario = make({"seed": 531, "fixture": FixtureMap.from_ascii(rows), "overrides": D.SHORT})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var bob: MinerHandle = s.add_miner("bob", s.fixture.spot("a") + Vector2i(2, 0))
	s.step(1)
	L.lit_in_hand(s, bob)
	s.step(5)
	D.fall(s, ann)
	s.step(2)
	var frame: Dictionary = s.run.vision.frame_for(ann.slot)
	var none: PackedInt32Array = frame["tiles"]["x"]
	assert_eq(none.size(), 0, "outside a window: nothing seen")
	assert_true(D.until_window(s, ann))
	s.step(2)
	frame = s.run.vision.frame_for(ann.slot)
	var me: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	var xs: PackedInt32Array = frame["tiles"]["x"]
	var ys: PackedInt32Array = frame["tiles"]["y"]
	assert_gt(xs.size(), 0, "her own cone, coming round")
	for i: int in xs.size():
		var t: Vector2 = Vector2(xs[i], ys[i]) + Vector2(0.5, 0.5)
		assert_lte(t.distance_to(me), 4.0 + 0.75, "within 4 tiles")
		assert_gt(s.run.light.light_at(Vector2i(xs[i], ys[i])), 0.0, "lit")
	# The crawl: the whole window moving, at most 4 tiles.
	var from: Vector2 = me
	ann.at(s.run.tick + 1).move(0.0, InputRecord.Gait.RUN, 200)
	s.run_until(func(_sv: Variant) -> bool: return not s.run.dark.in_window(ann.entity_id), 200)
	var crawled: float = s.run.registry.get_entity(ann.entity_id).position.distance_to(from)
	gut.p("crawled %.2f tiles in a window" % crawled)
	assert_gt(crawled, 0.5)
	assert_lte(crawled, 4.0 + 1e-3, "8 s at 0.5 tiles/s")
	# Voice in the next window: muffled to Bob, whisper events; 'Help!' at 12 np.
	assert_true(D.until_window(s, ann))
	var events_before: int = s.run.noise.event_log.size()
	var voice_before: int = bob.capture.messages.size()
	ann.at(s.run.tick + 1).say(3, 30)
	ann.at(s.run.tick + 1).callout("here", 3)
	s.step(40)
	var nps: Dictionary = {}
	for e: NoiseSystem.Event in s.run.noise.event_log.slice(events_before):
		if e.source_entity == ann.entity_id:
			nps[NoiseTypes.id_of(e.type)] = e.level_np
	assert_almost_eq(float(Variants.number(nps.get("voice", -1.0))), Tuning.f(&"voice.whisper_np"), 1e-6, "speech: whisper events")
	assert_almost_eq(float(Variants.number(nps.get("callout", -1.0))), Tuning.f(&"voice.talk_np"), 1e-6, "'Help!' at talk")
	var voices: int = 0
	var bad: Array[String] = []
	for m: Dictionary in bob.capture.messages.slice(voice_before):
		if int(Variants.number(m["type"])) == Protocol.Msg.VOICE:
			var vb: PackedByteArray = m["bytes"]
			var vp: PackedByteArray = Protocol.unframe(vb)["payload"]
			var h: Dictionary = VoicePackets.read_down(vp)
			if Variants.flag(h.get("probe", false)):
				continue
			voices += 1
			if not Variants.flag(h.get("muffled", false)) or int(Variants.number(h.get("band", 0))) != CalloutLines.WHISPER:
				bad.append("band %s muffled %s" % [h.get("band"), h.get("muffled")])
	gut.p("Bob got %d of her voice packets" % voices)
	assert_gt(voices, 10, "her speech reaches Bob")
	assert_eq(bad, [] as Array[String], "as a muffled whisper, though she shouted")
	var muffled: bool = false
	for m: Dictionary in bob.capture.messages.slice(voice_before):
		if int(Variants.number(m["type"])) == Protocol.Msg.CALLOUT:
			var bytes: PackedByteArray = m["bytes"]
			var body: PackedByteArray = Protocol.unframe(bytes)["payload"]
			var r: CalloutRecord = CalloutRecord.decode(body)
			assert_eq(VoiceManifest.line_of_wire(r.line), "help", "the wheel's top slice, coming round, is 'Help!'")
			muffled = true
	assert_true(muffled, "Bob heard her 'Help!'")
	assert_almost_eq(Tuning.f(&"voice.talk_np"), 12.0, 1e-6)
	assert_almost_eq(Tuning.f(&"voice.whisper_np"), 6.0, 1e-6)


func test_no_crawl_while_carried() -> void:
	var rows: PackedStringArray = ["##########################", "#........................#", "#..a.b...................#",
		"#........................#", "##########################"]
	var s: Scenario = make({"seed": 532, "fixture": FixtureMap.from_ascii(rows), "overrides": D.SHORT})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var bob: MinerHandle = s.add_miner("bob", s.fixture.spot("a") + Vector2i(1, 0))
	s.step(1)
	L.lit_in_hand(s, ann)
	assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.BLAST))
	s.step(2)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 42)
	s.step(1)
	assert_true(s.run.inventory.start_action(s.run, s.run.carry.lift_action(s.run, ann.entity_id, bob.entity_id)))
	s.step(45)
	assert_true(s.run.carry.is_carrying(ann.entity_id))
	assert_true(D.until_window(s, bob))
	bob.at(s.run.tick).move(180.0, InputRecord.Gait.WALK, 100)
	for _i: int in 100:
		s.step(1)
		if not s.run.dark.in_window(bob.entity_id):
			break
		assert_eq(s.run.registry.get_entity(bob.entity_id).position, s.run.registry.get_entity(ann.entity_id).position,
			"no crawl off the shoulder, tick %d" % s.run.tick)
