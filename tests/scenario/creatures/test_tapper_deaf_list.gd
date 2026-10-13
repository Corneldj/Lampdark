extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-08: deaf to light, other creatures and illusions (and the knocks and the hatch tick, which
## are never Road Graph events); voice-band events are heard even when every frame to every
## listener was dropped.

const T = preload("res://tests/scenario/creatures/tapper_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_deaf() -> void:
	var s: Scenario = make({"seed": 21, "fixture": T.road()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(30, 2))
	var h: TapperHearing = T.ears(s)
	s.run.light.grid.add_spot(0, Vector2i(1, 2), 1.0, 0)
	s.run.light.grid.add_point("flare", 2, 0, 0, 5.0, 1.0, Vector2(3.5, 2.5), 20)
	assert_eq(T.heard_now(s, h), 0, "light: nothing")
	s.place_stand_in(WorldIds.EntityKind.MOTH, Vector2i(4, 2))
	var moth: Creature = s.run.creatures.creature_of_kind(WorldIds.EntityKind.MOTH)
	s.run.noise.emit(NoiseTypes.Type.MOTH_LAYING, Vector2i(4, 2), {"source": moth.entity_id})
	assert_eq(T.heard_now(s, h), 0, "another creature's sound: nothing")
	s.run.replication.append_illusion_event(ann.slot, {"type": NoiseTypes.Type.VOICE, "start_tick": s.run.tick,
		"apparent": Vector2(3.5, 1.5), "remaining_np": 10.0, "duration_s": 1.0, "voice": 0})
	assert_eq(T.heard_now(s, h), 0, "an illusion is never a Road Graph event")
	s.run.noise.emit(NoiseTypes.Type.ROCK_TAP, Vector2i(4, 2), {"source": ann.entity_id})
	assert_eq(T.heard_now(s, h), 1, "a miner's tap is heard")


func test_voice_heard_with_every_frame_dropped() -> void:
	var s: Scenario = make({"seed": 22, "fixture": T.road()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(6, 2))
	var bob: MinerHandle = s.add_miner("bob", Vector2i(20, 2))
	s.step(2)
	ann.link(0, 100.0)
	bob.link(0, 100.0)
	var h: TapperHearing = T.ears(s)
	# SND-09 emits the voice band at the speaker from the server's own input, before any loss.
	T.voice(s, 5, Tuning.f(&"voice.talk_np"))
	assert_eq(T.heard_now(s, h), 1, "heard though every frame to every listener was dropped")
