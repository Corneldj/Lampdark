extends "res://tests/scenario/kit/scenario_test.gd"
## NET-05: a grab mid-walk hands the own miner to the server; local input moves nothing until
## the grab breaks and prediction resumes.


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_grab_mid_walk() -> void:
	var s: Scenario = make({"seed": 81, "fixture": FixtureMap.from_ascii(PackedStringArray(["#".repeat(40), "#a" + ".".repeat(37) + "#", "#".repeat(40)]))})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.run.light.grid.add_area("emergency", 3, 0, 0.6, range(40).map(func(x: int) -> Vector2i: return Vector2i(x, 1)))
	s.enable_prediction(ann)
	ann.at(0).move(0.0, InputRecord.Gait.WALK, 200)
	s.step(20)
	s.run.miner_state.enter_grabbed(ann.entity_id, &"drag", 77)
	s.step(6)
	assert_true(ann.prediction.server_driven, "the own block hands the miner to the server")
	var held: Vector2 = Vector2(ann.prediction.state.x, ann.prediction.state.y)
	s.step(20)
	assert_eq(Vector2(ann.prediction.state.x, ann.prediction.state.y), held, "walking input moves nothing")
	var server: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	assert_lt((held - server).length(), 0.01, "it stays where the server holds it")
	s.run.miner_state.end_grab(ann.entity_id, true)
	s.step(10)
	assert_false(ann.prediction.server_driven, "broken in time: predicted again")
	assert_gt(ann.prediction.state.x, held.x + 0.5, "and walking on")
