extends "res://tests/scenario/kit/scenario_test.gd"
## SND-09 (Gameplay §6.4, A.3; GDD §15.4, §15.5): an utterance counts as heard when at least half
## its frames were forwarded to a conscious human teammate; never to the deafened, unconscious or
## dead, a Hand (but for a predicate), or through a shut gate. Taps, live calls and callouts reset
## the timer through mark_heard; gasps, coughs and the Aside never do. Listener settings never
## enter it. The unheard mark falls at 60 s in ring 1 and 45 s from ring 2 down; a revive restarts
## the timer. The heard log follows the script.


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_each() -> void:
	super.after_each()
	WorldCoords.ring_override = -1


func _corridor() -> FixtureMap:
	return FixtureMap.from_ascii(PackedStringArray(["#".repeat(32), "#a" + ".".repeat(29) + "#", "#".repeat(32)]))


func _pair(seed_value: int, apart: int = 3) -> Array:
	var s: Scenario = make({"seed": seed_value, "fixture": _corridor()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var ben: MinerHandle = s.add_miner("ben", a + Vector2i(apart, 0))
	s.step(3)
	return [s, ann, ben]


## Says `band` for `ticks` frames, then ends the utterance as the client does.
func _utter(s: Scenario, h: MinerHandle, band: int, ticks: int) -> void:
	h.at(s.run.tick).say(band, ticks)
	s.step(ticks + 2)
	h.connection.send_voice(VoicePackets.end(h.voice_frames_sent))
	s.step(2)


func _causes(s: Scenario, slot: int) -> Array:
	var out: Array = []
	for e: Dictionary in s.run.heard.heard_log:
		if int(Variants.number(e["slot"])) == slot:
			out.append(e["cause"])
	return out


func test_half_the_frames_count_and_less_does_not() -> void:
	var p: Array = _pair(120)
	var s: Scenario = p[0]
	var ann: MinerHandle = p[1]
	var ben: MinerHandle = p[2]
	var h: HeardTracker = s.run.heard
	h.on_utterance(ann.slot, 100, {ben.slot: 49}, 2, true)
	s.step(1)
	assert_eq(h.heard_log.size(), 0, "49%: not heard")
	h.on_utterance(ann.slot, 100, {ben.slot: 50}, 2, true)
	s.step(1)  # applied on the next tick (VoiceFacts)
	assert_eq(_causes(s, ann.slot), [&"voice"], "50%: heard")
	assert_eq(h.utterances, 2)
	assert_eq(h.utterances_unheard, 1)


func test_a_real_utterance_to_a_teammate_is_heard() -> void:
	var p: Array = _pair(121)
	var s: Scenario = p[0]
	var ann: MinerHandle = p[1]
	_utter(s, ann, 2, 10)
	assert_eq(_causes(s, ann.slot), [&"voice"])
	assert_lt(s.run.heard.unheard_seconds(ann.slot), 0.25, "reset when the utterance closed")


func test_never_the_deafened_unconscious_dead_or_a_hand() -> void:
	for who: String in ["deafened", "unconscious", "dead", "hand"]:
		var p: Array = _pair(122)
		var s: Scenario = p[0]
		var ann: MinerHandle = p[1]
		var ben: MinerHandle = p[2]
		match who:
			"deafened":
				s.run.deafen.deafen(s.run, ben.slot, 30.0)
			"unconscious":
				s.run.miner_state.fall_unconscious(ben.entity_id, "test")
			"dead":
				s.run.miner_state.kill(ben.entity_id, "test")
			"hand":
				s.run.heard.is_hand = func(slot: int) -> bool: return slot == ben.slot
		s.step(1)
		assert_false(s.run.heard.eligible_listener(ben.slot), who)
		s.run.heard.on_utterance(ann.slot, 10, {ben.slot: 10}, 2, true)
		s.step(1)
		assert_eq(s.run.heard.heard_log.size(), 0, "%s: every frame delivered, still unheard" % who)


func test_a_predicate_counts_a_lone_human_by_a_hand() -> void:
	var p: Array = _pair(123)
	var s: Scenario = p[0]
	var ann: MinerHandle = p[1]
	var ben: MinerHandle = p[2]
	s.run.heard.is_hand = func(slot: int) -> bool: return slot == ben.slot
	var asked: Array = []
	s.run.heard.register_heard_predicate("lone_human", func(speaker: int, kind: StringName, band: int) -> bool:
		asked.append([speaker, kind, band])
		return true)
	s.run.heard.on_utterance(ann.slot, 10, {ben.slot: 10}, 2, true)
	s.step(1)
	assert_eq(_causes(s, ann.slot), [&"voice"], "RSC-09's lone human within 4 tiles of a Hand")
	assert_eq(asked, [[ann.slot, &"voice", 2]])
	assert_true(s.run.heard.callout_counts(ann.slot, {}, 2), "callouts ask the predicates too")


func test_a_shut_gate_on_the_path_never_counts() -> void:
	var rows: PackedStringArray = PackedStringArray(["#".repeat(20), "#a...G....b.......#", "#".repeat(20)])
	var s: Scenario = make({"seed": 124, "fixture": FixtureMap.from_ascii(rows)})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.add_miner("ben", s.fixture.spot("b"))
	s.step(3)
	_utter(s, ann, 3, 8)
	assert_eq(_causes(s, ann.slot), [], "shut gate: unheard")
	assert_true(s.set_gate(1, true))
	s.step(2)
	_utter(s, ann, 3, 8)
	assert_eq(_causes(s, ann.slot), [&"voice"], "open: heard")


func test_taps_calls_and_callouts_reset_and_nothing_else_does() -> void:
	var p: Array = _pair(125)
	var s: Scenario = p[0]
	var ann: MinerHandle = p[1]
	var ben: MinerHandle = p[2]
	var h: HeardTracker = s.run.heard
	for cause: StringName in [&"tap", &"call", &"callout"]:
		s.step(20)
		assert_gt(h.unheard_seconds(ann.slot), 0.9)
		assert_true(h.mark_heard(ann.slot, cause))
		assert_eq(h.unheard_seconds(ann.slot), 0.0, "%s resets the timer" % cause)
	assert_true(h.callout_counts(ann.slot, {ben.slot: 0.5}, 2), "a callout with half kept")
	assert_false(h.callout_counts(ann.slot, {ben.slot: 0.49}, 2))
	s.step(20)
	var before: float = h.unheard_seconds(ann.slot)
	for cause: StringName in [&"gasp", &"cough", &"breath_hold", &"aside", &"echo", &"signal", &"chalk"]:
		assert_false(h.mark_heard(ann.slot, cause), "%s never counts" % cause)
	var tile: Vector2i = s.run.registry.get_entity(ann.entity_id).tile()
	for type: NoiseTypes.Type in [NoiseTypes.Type.GASP, NoiseTypes.Type.COUGH]:
		s.run.noise.emit(type, tile, {"source": ann.entity_id})
	s.step(2)
	assert_almost_eq(h.unheard_seconds(ann.slot), before + 0.1, 1e-6, "gasps and coughs reach Ben and reset nothing")
	# The Aside: whispered to no one.
	s.run.voice.set_route(ann.slot, VoiceRoutes.Route.ASIDE)
	var n: int = h.heard_log.size()
	_utter(s, ann, 1, 10)
	assert_eq(h.heard_log.size(), n, "the Aside is never heard")


func test_a_listeners_settings_change_nothing() -> void:
	var p: Array = _pair(126)
	var s: Scenario = p[0]
	var ann: MinerHandle = p[1]
	var ben: MinerHandle = p[2]
	# Ben has muted his own microphone and turned voices off locally: the server never learns the
	# volume, and his own mic label is about him, not what he hears.
	for session: Sessions.Session in s.net.sessions.welcomed():
		if session.slot == ben.slot:
			session.mute_label = true
	ben.connection.voice_in.clear()
	_utter(s, ann, 2, 8)
	assert_eq(_causes(s, ann.slot), [&"voice"], "delivery decides, not what Ben's client does with it")


func test_the_unheard_mark_by_ring() -> void:
	for ring: int in [1, 2, 4]:
		WorldCoords.ring_override = ring
		var s: Scenario = make({"seed": 127 + ring, "fixture": _corridor()})
		var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
		var limit: float = 60.0 if ring == 1 else 45.0
		s.step(roundi(limit * 20.0) - s.run.tick)
		assert_false(s.run.heard.past_unheard_mark(ann.slot), "ring %d: at %.0f s, not yet" % [ring, limit])
		s.step(1)
		assert_true(s.run.heard.past_unheard_mark(ann.slot), "ring %d: past %.0f s" % [ring, limit])
		s.run.heard.mark_heard(ann.slot, &"tap")
		assert_false(s.run.heard.past_unheard_mark(ann.slot), "heard: clear")


func test_a_revive_restarts_the_timer() -> void:
	var p: Array = _pair(130)
	var s: Scenario = p[0]
	var ben: MinerHandle = p[2]
	s.run.miner_state.fall_unconscious(ben.entity_id, "test")
	s.step(40)
	assert_gt(s.run.heard.unheard_seconds(ben.slot), 2.0)
	s.run.miner_state.revive(ben.entity_id, &"test")
	s.step(1)
	assert_lt(s.run.heard.unheard_seconds(ben.slot), 0.11, "revived: the timer starts again")
	assert_eq(_causes(s, ben.slot), [], "a revive is not being heard")


func test_the_heard_log_follows_the_script() -> void:
	var p: Array = _pair(131)
	var s: Scenario = p[0]
	var ann: MinerHandle = p[1]
	var ben: MinerHandle = p[2]
	_utter(s, ann, 2, 6)
	var t1: int = s.run.tick
	s.step(10)
	s.run.heard.mark_heard(ben.slot, &"tap")
	var t2: int = s.run.tick
	s.step(10)
	s.run.voice.open_direct(ann.slot, ben.slot)  # LFT-12's stub: a live call marks both ends
	s.run.heard.mark_heard(ann.slot, &"call")
	s.run.heard.mark_heard(ben.slot, &"call")
	var log: Array = []
	for e: Dictionary in s.run.heard.heard_log:
		log.append([e["slot"], e["cause"]])
	assert_eq(log, [[ann.slot, &"voice"], [ben.slot, &"tap"], [ann.slot, &"call"], [ben.slot, &"call"]])
	assert_lte(int(Variants.number(s.run.heard.heard_log[0]["tick"])), t1)
	assert_eq(int(Variants.number(s.run.heard.heard_log[1]["tick"])), t2)
	var secs: PackedFloat64Array = s.run.heard.band_seconds[ann.slot]
	assert_almost_eq(secs[2], 6 * VoicePackets.FRAME_S, 1e-9, "the band's seconds for the record")
