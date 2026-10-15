extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-04: the dead keep the dream channel and watching only (no windows, no game sound, no callout);
## a player who drops while unconscious and rejoins returns to the Dark: blinded, the window schedule
## as it was, the dream channel, and the watch started again from a keyframe for the new client.

const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")
const D = preload("res://tests/scenario/rescue/dark_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _count(h: MinerHandle, type: Protocol.Msg, from_index: int) -> int:
	var n: int = 0
	for m: Dictionary in h.capture.messages.slice(from_index):
		if int(Variants.number(m["type"])) == type:
			n += 1
	return n


func test_the_dead_keep_the_dream_and_watching() -> void:
	var s: Scenario = make({"seed": 561, "fixture": "test", "overrides": D.SHORT})
	var miners: Array[MinerHandle] = D.W.crew(s, 3, 561)
	var ann: MinerHandle = miners[0]
	var bob: MinerHandle = miners[1]
	var cid: MinerHandle = miners[2]
	ann.brain = null
	bob.brain = null
	s.step(5)
	D.fall(s, ann)
	s.run.miner_state.kill(ann.entity_id, "test")
	s.run.miner_state.kill(bob.entity_id, "test")  # killed outright, never unconscious
	s.step(2)
	var dead_at: int = s.run.tick
	assert_true(D.fallen(s, ann).dead and D.fallen(s, bob).dead, "both dead in the Dark")
	var from: int = ann.capture.messages.size()
	var bob_from: int = bob.capture.messages.size()
	var events_before: int = s.run.noise.event_log.size()
	ann.at(s.run.tick + 1).press(ActionRecord.Kind.WATCH, 1)
	ann.at(s.run.tick + 5).callout("here", 2)
	cid.at(s.run.tick + 1).say(3, 20)
	bob.at(s.run.tick + 40).say(2, 20)
	ann.at(s.run.tick + 80).say(2, 20)
	s.step(950)  # watching starts once the run is 45 s old
	assert_eq(s.run.dark.windows_log.size(), 0, "no window in 47 s of short spells: the dead never come round")
	assert_eq(s.run.callouts.spoken.filter(func(c: Dictionary) -> bool: return int(Variants.number(c.get("slot", -1))) == ann.slot).size(), 0,
		"no callout")
	var made: int = 0
	for e: NoiseSystem.Event in s.run.noise.event_log.slice(events_before):
		if e.source_entity == ann.entity_id or e.source_entity == bob.entity_id:
			made += 1
	assert_eq(made, 0, "no noise of theirs")
	var heard: int = 0
	for e: Dictionary in ann.capture.audio_events(dead_at, s.run.tick):
		if not VisualEvents.is_visual(int(Variants.number(e["type"]))):
			heard += 1
	var living: int = 0
	for e: Dictionary in cid.capture.audio_events(dead_at, s.run.tick):
		if not VisualEvents.is_visual(int(Variants.number(e["type"]))):
			living += 1
	gut.p("game sounds after the deaths: Ann %d, Cid %d" % [heard, living])
	assert_gt(living, 0, "there was game sound to hear")
	assert_eq(heard, 0, "no game sound for the dead")
	assert_gt(_count(ann, Protocol.Msg.VOICE, from), 10, "the dream channel: Bob's voice")
	assert_gt(_count(ann, Protocol.Msg.WATCH, from), 0, "and watching")
	assert_eq(D.fallen(s, ann).watching, cid.slot, "Cid, the one conscious teammate")
	assert_gt(_count(bob, Protocol.Msg.VOICE, bob_from), 0, "Bob, killed outright, is on the dream channel too")


func test_a_rejoining_player_returns_to_the_dark() -> void:
	var s: Scenario = make({"seed": 562, "fixture": "test", "overrides": {"rescue.coming_round_interval_s": [30.0, 40.0]}})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var miners: Array[MinerHandle] = D.W.crew(s, 3, 562)
	var ann: MinerHandle = miners[0]
	var bob: MinerHandle = miners[1]
	ann.brain = null
	bob.brain = null
	s.step(5)
	D.fall(s, ann)
	D.fall(s, bob)
	ann.at(s.run.tick + 1).press(ActionRecord.Kind.WATCH, 1)
	s.step(950)
	var f: DarkSystem.Fallen = D.fallen(s, ann)
	var next_window: int = f.next_window
	var slot: int = ann.slot
	assert_true(f.watching >= 0, "watching before the drop")
	ann.at(s.run.tick + 1).disconnect_at()
	s.step(40)
	ann.at(s.run.tick + 1).reconnect_at()
	var from: int = ann.capture.messages.size()
	bob.at(s.run.tick + 20).say(2, 30)
	s.step(80)
	assert_eq(ann.slot, slot, "the same seat")
	assert_eq(D.fallen(s, ann), f, "still in the Dark")
	assert_eq(f.next_window, next_window, "the window schedule as it was")
	var seen: PackedInt32Array = s.run.vision.frame_for(ann.slot)["tiles"]["x"]
	assert_eq(seen.size(), 0, "blind")
	assert_gt(_count(ann, Protocol.Msg.FRAME, from), 40, "frames again")
	assert_gt(_count(ann, Protocol.Msg.VOICE, from), 10, "the dream channel: Bob")
	var first_watch: Dictionary = {}
	for m: Dictionary in ann.capture.messages.slice(from):
		if int(Variants.number(m["type"])) == Protocol.Msg.WATCH:
			var bytes: PackedByteArray = m["bytes"]
			var payload: PackedByteArray = Protocol.unframe(bytes)["payload"]
			first_watch = DarkMessages.decode(payload)
			break
	assert_false(first_watch.is_empty(), "the watch goes on")
	assert_true(Variants.flag(first_watch.get("reset", false)), "from a keyframe for the new client")
	for v: Dictionary in audit.violations.slice(0, 12):
		gut.p("VIOLATION %s" % v)
	assert_eq(audit.violation_count, 0, "a rejoined client gets nothing beyond the Dark")
