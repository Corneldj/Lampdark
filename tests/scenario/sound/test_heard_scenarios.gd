extends "res://tests/scenario/kit/scenario_test.gd"
## SND-09 end to end over the kit's network: talk near the edge of range while running fails some
## utterances and the timer follows each one; a deafened listener hears nothing and nobody is
## heard until the ringing stops; a phone line (LFT-12 stub) carries voice both ways, heard.


func before_all() -> void:
	assert_true(Tuning.load_server())


func _corridor() -> FixtureMap:
	return FixtureMap.from_ascii(PackedStringArray(["#".repeat(32), "#a" + ".".repeat(29) + "#", "#".repeat(32)]))


func _end(s: Scenario, h: MinerHandle) -> void:
	h.connection.send_voice(VoicePackets.end(h.voice_frames_sent))
	s.step(2)


func test_talk_at_the_edge_while_running_fails_some_utterances() -> void:
	var s: Scenario = make({"seed": 140, "fixture": _corridor()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var ben: MinerHandle = s.add_miner("ben", a + Vector2i(11, 0))
	s.step(3)
	var heard: int = 0
	var failed: int = 0
	for i: int in 30:
		# Ann runs into the wall behind her (she stays put, running) and talks for a second.
		ann.at(s.run.tick).say(2, 20).move(180.0, InputRecord.Gait.RUN, 22)
		s.step(22)
		var before: int = s.run.heard.heard_log.size()
		var unheard_before: float = s.run.heard.unheard_seconds(ann.slot)
		_end(s, ann)
		var r: Dictionary = Variants.dict(Variants.dict(s.run.voice._speaking[ann.slot]).get("rates", {})).get(ben.slot, {})
		if i == 0:
			gut.p("rates at 11 tiles, running: %s" % r)
		if s.run.heard.heard_log.size() > before:
			heard += 1
			assert_lt(s.run.heard.unheard_seconds(ann.slot), 0.2, "heard: the timer restarts")
		else:
			failed += 1
			assert_gt(s.run.heard.unheard_seconds(ann.slot), unheard_before, "unheard: the timer runs on")
		s.step(1)
	gut.p("30 utterances at 11 tiles while running: %d heard, %d failed" % [heard, failed])
	assert_gt(heard, 0)
	assert_gt(failed, 0, "some utterances at the edge, running, never arrive")
	assert_eq(s.run.heard.utterances_unheard, failed)


func test_a_deafened_listener_hears_nobody() -> void:
	var s: Scenario = make({"seed": 141, "fixture": _corridor()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var ben: MinerHandle = s.add_miner("ben", a + Vector2i(3, 0))
	s.step(3)
	s.run.deafen.deafen(s.run, ben.slot, 5.0)
	ann.at(s.run.tick).say(3, 10)
	s.step(12)
	_end(s, ann)
	assert_eq(s.run.heard.heard_log.size(), 0, "a shout at 3 tiles to a deafened teammate: unheard")
	s.step(roundi(5.0 * 20.0))
	ann.at(s.run.tick).say(2, 10)
	s.step(12)
	_end(s, ann)
	assert_eq(s.run.heard.heard_log.size(), 1, "the ringing over: heard")


func test_a_phone_line_is_heard_both_ways() -> void:
	var s: Scenario = make({"seed": 142, "fixture": _corridor()})
	var a: Vector2i = s.fixture.spot("a")
	var caller: MinerHandle = s.add_miner("ann", a)
	var operator: MinerHandle = s.add_miner("ben", a + Vector2i(28, 0))  # far beyond a whisper
	s.step(3)
	s.run.voice.open_direct(caller.slot, operator.slot)
	for h: MinerHandle in [caller, operator]:
		h.at(s.run.tick).say(1, 10)
		s.step(12)
		_end(s, h)
	var causes: Array = []
	for e: Dictionary in s.run.heard.heard_log:
		causes.append([e["slot"], e["cause"]])
	assert_eq(causes, [[caller.slot, &"voice"], [operator.slot, &"voice"]], "the caller and the operator hear each other")


func test_voice_replays_from_the_input_log() -> void:
	var s: Scenario = make({"seed": 143, "fixture": _corridor()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	s.add_miner("ben", a + Vector2i(11, 0))
	s.step(3)
	for i: int in 6:
		ann.at(s.run.tick).say(2 + i % 2, 15).move(180.0, InputRecord.Gait.RUN, 16)
		s.step(16)
		_end(s, ann)
	var path: String = "user://snd09_voice_replay.jsonl"
	assert_eq(s.save_replay(path), OK)
	assert_gt(s.recorder.voice_by_tick.size(), 0, "voice facts were logged")
	var r: Scenario = Scenario.replay(path)
	_made.append(r)
	assert_eq(r.state_hash(), s.state_hash(), "voice's effects replay with no network")
	assert_eq(r.run.heard.heard_log, s.run.heard.heard_log, "the same utterances heard, on the same ticks")
	var voice_events: Array[int] = [0, 0]
	for i: int in 2:
		var run: RunState = s.run if i == 0 else r.run
		for e: NoiseSystem.Event in run.noise.event_log:
			if e.type == NoiseTypes.Type.VOICE:
				voice_events[i] += 1
	assert_gt(voice_events[0], 0)
	assert_eq(voice_events[1], voice_events[0], "the same band events")
