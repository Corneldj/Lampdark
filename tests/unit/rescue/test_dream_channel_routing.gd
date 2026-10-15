extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-04: a fallen player's voice reaches every other fallen or dead player and no conscious one; it
## raises no Road Graph event (so no creature hears it) and earns nobody a heard credit. A dead player
## talks on it too.

const D = preload("res://tests/scenario/rescue/dark_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _voice_frames(h: MinerHandle) -> int:
	var n: int = 0
	for m: Dictionary in h.capture.messages:
		if int(Variants.number(m["type"])) == Protocol.Msg.VOICE:
			n += 1
	return n


func test_the_fallen_talk_only_among_themselves() -> void:
	var s: Scenario = make({"seed": 511, "fixture": "test"})
	var miners: Array[MinerHandle] = D.W.crew(s, 4, 511)
	var ann: MinerHandle = miners[0]
	var bob: MinerHandle = miners[1]
	var cid: MinerHandle = miners[2]
	var dot: MinerHandle = miners[3]
	s.step(5)
	D.fall(s, ann)
	D.fall(s, bob)
	s.run.miner_state.kill(dot.entity_id, "test")
	s.step(60)
	var bob_before: int = _voice_frames(bob)
	var cid_before: int = _voice_frames(cid)
	var dot_before: int = _voice_frames(dot)
	var events_before: int = s.run.noise.event_log.size()
	var unheard_before: float = s.run.heard.unheard_seconds(ann.slot)
	ann.at(s.run.tick + 1).say(3, 40)
	s.step(60)
	assert_gt(_voice_frames(bob) - bob_before, 20, "another fallen miner hears her")
	assert_gt(_voice_frames(dot) - dot_before, 20, "and the dead")
	assert_eq(_voice_frames(cid) - cid_before, 0, "the living never")
	var voice_events: int = 0
	for e: NoiseSystem.Event in s.run.noise.event_log.slice(events_before):
		if e.source_entity == ann.entity_id:
			voice_events += 1
	assert_eq(voice_events, 0, "no Road Graph event: nothing hears it")
	assert_gt(s.run.heard.unheard_seconds(ann.slot), unheard_before, "and no heard credit")
	dot.at(s.run.tick + 1).say(2, 20)
	var ann_before: int = _voice_frames(ann)
	s.step(40)
	assert_gt(_voice_frames(ann) - ann_before, 10, "the dead talk on it too")
