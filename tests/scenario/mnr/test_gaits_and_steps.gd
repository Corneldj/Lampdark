extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-01 (scn_gaits_and_steps): a miner walks 12 tiles of road in 4.0 s +/- 1 tick with 8 step
## events, and two miners can stand on the same spot.


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_twelve_tiles_of_road() -> void:
	var s: Scenario = make({"seed": 30, "fixture": FixtureMap.from_ascii(PackedStringArray(["#".repeat(30), "#a" + ".".repeat(27) + "#", "#".repeat(30)]))})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var start_x: float = s.run.registry.get_entity(ann.entity_id).position.x
	ann.at(0).move(0.0, InputRecord.Gait.WALK, 200)
	var arrived: Array[int] = [-1]
	s.on_tick = func(sc: Scenario) -> void:
		if arrived[0] < 0 and sc.run.registry.get_entity(ann.entity_id).position.x - start_x >= 12.0 - 1e-4:
			arrived[0] = sc.run.tick
	s.step(100)
	var first_moving: int = s.run.inputs.recorder.by_tick.keys().filter(func(t: Variant) -> bool:
		var item: Array = Variants.array(Variants.array(s.run.inputs.recorder.by_tick[t])[0])
		var c: InputBuffer.Consumed = item[1]
		return c.record.move_dir != InputRecord.NO_DIRECTION).min()
	var ticks: int = arrived[0] - first_moving
	assert_true(absi(ticks - 80) <= 1, "12 tiles at 3.0 tiles/s: 80 ticks +/- 1, took %d" % ticks)
	var steps: Array = s.run.noise.event_log.filter(func(e: NoiseSystem.Event) -> bool: return e.type == NoiseTypes.Type.STEP_WALK and e.tick <= arrived[0])
	assert_eq(steps.size(), 8, "8 step events over the 12 tiles")


func test_miners_share_a_spot() -> void:
	var s: Scenario = make({"seed": 31, "fixture": FixtureMap.from_ascii(PackedStringArray(["#######", "#a....#", "#######"]))})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var bob: MinerHandle = s.add_miner("bob", s.fixture.spot("a") + Vector2i(2, 0))
	bob.at(0).move(180.0, InputRecord.Gait.WALK, 14)
	s.step(16)
	var a: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	var b: Vector2 = s.run.registry.get_entity(bob.entity_id).position
	assert_lt(b.x, a.x + 0.01, "Bob walked onto and past Ann's spot: miners never block miners")
