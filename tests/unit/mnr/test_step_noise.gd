extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-01's steps through SND-02: walking 9 np every 10 ticks, running 18 np, crouching none,
## and stop-start movement cannot dodge them.




func before_all() -> void:
	assert_true(Tuning.load_server())


func _steps(s: Scenario, type: NoiseTypes.Type) -> Array:
	return s.run.noise.event_log.filter(func(e: NoiseSystem.Event) -> bool: return e.type == type)


func _road() -> Scenario:
	var road: PackedStringArray = PackedStringArray(["#".repeat(60), "#a" + ".".repeat(57) + "#", "#".repeat(60)])
	return make({"seed": 21, "fixture": FixtureMap.from_ascii(road)})


func test_walk_run_and_crouch() -> void:
	var s: Scenario = _road()
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	ann.at(0).move(0.0, InputRecord.Gait.WALK, 40)
	s.step(42)
	var walks: Array = _steps(s, NoiseTypes.Type.STEP_WALK)
	assert_eq(walks.size(), 4, "40 ticks of walking: a step every 10")
	var ticks: Array[int] = []
	for raw: Variant in walks:
		var e: NoiseSystem.Event = raw
		ticks.append(e.tick)
	assert_eq([ticks[1] - ticks[0], ticks[2] - ticks[1], ticks[3] - ticks[2]], [10, 10, 10])
	var first: NoiseSystem.Event = walks[0]
	assert_eq(first.level_np, 9.0)
	var t: Scenario = _road()
	var bob: MinerHandle = t.add_miner("bob", t.fixture.spot("a"))
	bob.at(0).move(0.0, InputRecord.Gait.RUN, 20)
	t.step(22)
	var runs: Array = _steps(t, NoiseTypes.Type.STEP_RUN)
	assert_eq(runs.size(), 2)
	var run_step: NoiseSystem.Event = runs[0]
	assert_eq(run_step.level_np, 18.0)
	var c: Scenario = _road()
	var cat: MinerHandle = c.add_miner("cat", c.fixture.spot("a"))
	cat.at(0).move(0.0, InputRecord.Gait.CROUCH, 60)
	c.step(62)
	assert_eq(c.run.noise.event_log.size(), 0, "crouching is silent")
	assert_gt(c.run.registry.get_entity(cat.entity_id).position.x, 3.0, "though it moved")


func test_stop_start_cannot_dodge_steps() -> void:
	var s: Scenario = _road()
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	for i: int in 5:
		ann.at(i * 12).move(0.0, InputRecord.Gait.WALK, 6)  # 0.3 s moving, 0.3 s stopped
	s.step(64)
	assert_eq(_steps(s, NoiseTypes.Type.STEP_WALK).size(), 3, "1.5 s of movement: one step per 0.5 s")


func test_a_step_override_makes_heavy_steps() -> void:
	var s: Scenario = _road()
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.run.movement.modifiers(ann.slot).set_modifier(&"test_mud", 0.5, 12.0)
	ann.at(0).move(0.0, InputRecord.Gait.WALK, 40)
	s.step(42)
	var heavy: Array = _steps(s, NoiseTypes.Type.STEP_HEAVY)
	assert_eq(heavy.size(), 4, "mud: 12 np steps")
	assert_eq(_steps(s, NoiseTypes.Type.STEP_WALK).size(), 0)
