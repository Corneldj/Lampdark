extends "res://tests/scenario/kit/scenario_test.gd"
## SND-03 with HAZ-04: a firedamp pocket hisses faintly ('[gas hissing]') inside and within 2 tiles:
## Ann, beside it, receives the hiss as a local record and her client plays it on the Ambience bus;
## Bob, 4 tiles off, receives nothing; the Road Graph, the creatures and the collapse hook never hear it.

const A = preload("res://tests/unit/sound/audio_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_only_within_two_tiles() -> void:
	var s: Scenario = make({"seed": 112, "fixture": A.hall()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(8, 3))
	var bob: MinerHandle = s.add_miner("bob", Vector2i(13, 3))
	s.step(2)
	var events_before: int = s.run.noise.event_log.size()
	for i: int in 3:
		s.run.audio.local(s.run, LocalSounds.Type.FIREDAMP_HISS, Vector2i(9, 3), 2.0, 2.0, 1.0)
		s.step(20)
	var ann_hiss: Array[Dictionary] = []
	for e: Dictionary in ann.connection.events:
		if int(Variants.number(e["type"])) == LocalSounds.Type.FIREDAMP_HISS:
			ann_hiss.append(e)
	var bob_hiss: int = 0
	for e: Dictionary in bob.connection.events:
		if int(Variants.number(e["type"])) == LocalSounds.Type.FIREDAMP_HISS:
			bob_hiss += 1
	assert_eq(ann_hiss.size(), 3, "Ann hears each hiss")
	assert_eq(bob_hiss, 0, "Bob, 4 tiles off, none")
	var r: AudioRecord = AudioRecord.from_event(ann_hiss[0])
	assert_eq(r.flags & AudioRecord.LOCAL, AudioRecord.LOCAL)
	assert_eq(EventPlayer.bus_for(r), "Ambience", "ambient, not a Road Graph sound")
	assert_eq(s.run.noise.event_log.size(), events_before, "no Road Graph event (so no creature delivery or collapse check)")
