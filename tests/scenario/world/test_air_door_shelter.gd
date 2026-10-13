extends "res://tests/scenario/kit/scenario_test.gd"
## GEN-15 (Gameplay §6.1, §5.2): a shut air door is shelter. No light crosses it from a source on
## the other side, no sight crosses it, and a sound beyond it arrives 12 np weaker than through the
## open door; open, it does none of these.

const W = preload("res://tests/unit/world/door_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _world(run_seed: int, open: bool) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": W.corridor()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(12, 1), {"facing_deg": 0.0})
	ann.at(0).face(0.0)
	var bob: MinerHandle = s.add_miner("bob", Vector2i(20, 1))
	s.run.lamps.create(s.run, 1.0, 3, true, LampRules.WICK_UP, Vector2(13.5, 1.5))
	if open:
		s.run.air_doors._flip(s.run, W.door(s), true)
	s.step(4)
	return [s, ann, bob]


func test_light_sight_and_sound() -> void:
	var shut: Array = _world(7, false)
	var open: Array = _world(7, true)
	var ss: Scenario = shut[0]
	var so: Scenario = open[0]
	assert_eq(ss.run.light.light_at(Vector2i(16, 1)), 0.0, "shut: no light beyond it")
	assert_gt(so.run.light.light_at(Vector2i(16, 1)), 0.0, "open: light passes")
	var sa: MinerHandle = shut[1]
	var oa: MinerHandle = open[1]
	assert_false(sa.connection.view.tiles.has(Vector2i(16, 1)), "shut: Ann sees nothing beyond")
	assert_true(oa.connection.view.tiles.has(Vector2i(16, 1)), "open: she does")
	var shot: Array[float] = []
	var voice: Array[int] = []
	for pair: Array in [shut, open]:
		var sc: Scenario = pair[0]
		var ann: MinerHandle = pair[1]
		var bob: MinerHandle = pair[2]
		sc.run.noise.emit(NoiseTypes.Type.SHOT, Vector2i(11, 1), {})
		# A voice loud enough to clear the door's 12 np (a scream's 28): a shut door still cuts it.
		sc.run.noise.emit(NoiseTypes.Type.VOICE, Vector2i(12, 1), {"level_np": Tuning.f(&"voice.scream_np"), "voice_id": 0,
			"mode": RoadGraphService.MODE_VOICE, "source": ann.entity_id})
		sc.step(3)
		var got: float = -1.0
		var voices: int = 0
		for e: Dictionary in bob.connection.events:
			if int(Variants.number(e["type"])) == NoiseTypes.Type.SHOT:
				got = float(Variants.number(e["remaining_np"]))
			elif int(Variants.number(e["type"])) == NoiseTypes.Type.VOICE:
				voices += 1
		shot.append(got)
		voice.append(voices)
	assert_gt(shot[0], 0.0, "shut: the shot still reaches Bob")
	assert_almost_eq(shot[1] - shot[0], 12.0, 0.3, "shut: 12 np weaker (%.2f open, %.2f shut)" % [shot[1], shot[0]])
	assert_eq(voice[1], 1, "open: Bob hears the voice")
	assert_eq(voice[0], 0, "shut: voice is cut completely, not muffled")
