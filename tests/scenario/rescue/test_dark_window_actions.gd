extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-04, a whole spell in the Dark under NET-08's audit: at the fall the victim gets their own view
## of the moments before and nothing else from the window; outside a window nothing of the mine and
## only muffled game sound round the body; in a window the crawl, speech at whisper, 'Help!' and the
## moan, each a real event; the window's telemetry; and no audit violation anywhere.

const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")
const D = preload("res://tests/scenario/rescue/dark_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _payloads(h: MinerHandle, type: Protocol.Msg, from_index: int = 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m: Dictionary in h.capture.messages.slice(from_index):
		if int(Variants.number(m["type"])) == type:
			var bytes: PackedByteArray = m["bytes"]
			out.append({"tick": int(Variants.number(m["tick"])), "payload": Protocol.unframe(bytes)["payload"]})
	return out


func test_a_spell_in_the_dark() -> void:
	var s: Scenario = make({"seed": 541, "fixture": "test", "overrides": D.SHORT})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var miners: Array[MinerHandle] = D.W.crew(s, 3, 541)
	var ann: MinerHandle = miners[0]
	ann.brain = null
	miners[1].at(10).say(2, 30)
	s.step(60)
	D.fall(s, ann)
	var f: DarkSystem.Fallen = D.fallen(s, ann)
	assert_not_null(f, "Ann is in the Dark")
	# At the fall: her own view, once the window seals.
	assert_true(s.run_until(func(_sv: Variant) -> bool: return f.replay_sent, 400), "the replay is sent")
	s.step(1)
	# What Ann was sent, by frame tick.
	var own: Dictionary = {}
	for m: Dictionary in _payloads(ann, Protocol.Msg.FRAME):
		var payload: PackedByteArray = m["payload"]
		own[int(Variants.number(FrameDecoder.header(payload)["tick"]))] = payload
	var replayed: int = 0
	var bad: Array[String] = []
	for m: Dictionary in _payloads(ann, Protocol.Msg.REPLAY):
		var payload: PackedByteArray = m["payload"]
		var d: Dictionary = DarkMessages.decode(payload)
		for raw: Variant in Variants.array(d["frames"]):
			var fr: Array = raw
			var t: int = fr[0]
			var bytes: PackedByteArray = fr[1]
			replayed += 1
			if t > f.fell_tick:
				bad.append("frame %d after the fall" % t)
			elif not own.has(t) or own[t] != bytes:
				bad.append("frame %d is not her own" % t)
	gut.p("replayed %d of her own frames" % replayed)
	assert_gt(replayed, 30)
	assert_eq(bad, [] as Array[String], "her own frames, up to the fall, nothing else")
	assert_eq(_payloads(ann, Protocol.Msg.WATCH).size(), 0, "no watching unasked")
	# Windows: the crawl, speech, 'Help!' and the moan.
	assert_true(D.until_window(s, ann), "a window opens")
	var events_before: int = s.run.noise.event_log.size()
	ann.at(s.run.tick + 1).move(90.0, InputRecord.Gait.WALK, 150)
	ann.at(s.run.tick + 1).say(1, 20)
	ann.at(s.run.tick + 2).callout("here", 2)
	s.step(30)
	ann.at(s.run.tick + 1).callout(CalloutLines.WHEEL[6], 2)
	s.run_until(func(_sv: Variant) -> bool: return not s.run.dark.in_window(ann.entity_id), 200)
	var kinds: Dictionary = {}
	for e: NoiseSystem.Event in s.run.noise.event_log.slice(events_before):
		if e.source_entity == ann.entity_id:
			var k: String = NoiseTypes.id_of(e.type)
			kinds[k] = Variants.array(kinds.get(k, [])) + [e.level_np]
	gut.p("her window's events: %s" % kinds)
	assert_true(Variants.array(kinds.get("voice", [])).has(Tuning.f(&"voice.whisper_np")), "her speech: 6 np")
	assert_true(Variants.array(kinds.get("callout", [])).has(Tuning.f(&"voice.talk_np")), "'Help!': 12 np")
	assert_true(Variants.array(kinds.get("callout", [])).has(Tuning.f(&"voice.whisper_np")), "the moan: 6 np")
	assert_eq(s.run.dark.windows_log.size(), 1)
	var w: Dictionary = s.run.dark.windows_log[0]
	assert_eq(int(Variants.number(w["close"])) - int(Variants.number(w["open"])), 160, "8 s, 160 ticks")
	# Back in the black, for a while longer.
	s.step(40)
	var frame: Dictionary = s.run.vision.frame_for(ann.slot)
	var xs: PackedInt32Array = frame["tiles"]["x"]
	assert_eq(xs.size(), 0, "nothing of the mine outside a window")
	var r: Dictionary = audit.report()
	gut.p("judged: %s" % r["checked"])
	for v: Dictionary in audit.violations.slice(0, 12):
		gut.p("VIOLATION %s" % v)
	assert_eq(audit.violation_count, 0, "no audit violation through the spell")
	var checked: Dictionary = r["checked"]
	for rule: String in ["frame", "audio", "replay"]:
		assert_gt(int(Variants.number(checked.get(rule, 0))), 0, "%s records were judged" % rule)
