extends "res://tests/scenario/kit/scenario_test.gd"
## SND-03: a local emitter (the firedamp hiss, '[gas hissing]') reaches only clients within its
## radius, flagged LOCAL, and makes no Road Graph event, no creature delivery and no collapse check.

const A = preload("res://tests/unit/sound/audio_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_hiss_within_two_tiles_only() -> void:
	var s: Scenario = make({"seed": 4, "fixture": A.hall()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(10, 3))
	var bob: MinerHandle = s.add_miner("bob", Vector2i(14, 3))
	s.step(2)
	var got: Array[Array] = A.capture(s)
	var events_before: int = s.run.noise.event_log.size()
	var creature_calls: Array[int] = [0]
	s.run.noise.creature_hooks.append(func(_e: NoiseSystem.Event, _d: Dictionary) -> void: creature_calls[0] += 1)
	var sent: int = s.run.audio.local(s.run, LocalSounds.Type.FIREDAMP_HISS, Vector2i(11, 3), 2.0, 3.0, 1.0)
	assert_eq(sent, 1, "one client within 2 tiles")
	assert_eq(got.size(), 1)
	var first: Array = got[0]
	assert_eq(int(Variants.number(first[0])), ann.slot, "Ann, 1 tile away")
	var r: AudioRecord = first[1]
	assert_eq(r.flags & AudioRecord.LOCAL, AudioRecord.LOCAL)
	assert_eq(r.type, LocalSounds.Type.FIREDAMP_HISS)
	s.step(3)
	# NoiseSystem runs the collapse hook only while dispatching an event, which it then logs: an
	# unchanged log is no Road Graph event and no collapse check.
	assert_eq(s.run.noise.event_log.size(), events_before, "no Road Graph event, so no collapse check")
	assert_eq(creature_calls[0], 0, "no creature delivery")
	var bob_heard: int = 0
	for e: Dictionary in bob.connection.events:
		if int(Variants.number(e["type"])) == LocalSounds.Type.FIREDAMP_HISS:
			bob_heard += 1
	assert_eq(bob_heard, 0, "Bob, 3.5 tiles away, hears nothing")
