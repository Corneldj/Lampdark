extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-02 (scn_run_and_pant): six seconds of running down a road, then a stop: twelve 18 np
## steps, then four 9 np panting events. A listener 8 tiles away by path hears all four; one 10
## tiles away hears none.

const W = preload("res://tests/unit/mnr/stamina_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_run_and_pant() -> void:
	var s: Scenario = make({"seed": 77, "fixture": W.road(60)})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	ann.at(0).move(0.0, InputRecord.Gait.RUN, 121)
	s.step(130)
	var stop: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	var near: MinerHandle = s.add_miner("near", Vector2i(floori(stop.x) + 8, 1))
	var far: MinerHandle = s.add_miner("far", Vector2i(floori(stop.x) + 10, 1))
	s.step(200)
	var steps: Array = s.run.noise.event_log.filter(func(e: NoiseSystem.Event) -> bool: return e.type == NoiseTypes.Type.STEP_RUN)
	assert_eq(steps.size(), 12, "twelve running steps")
	var pants: Array = W.pants(s)
	assert_eq(pants.size(), 4, "four panting events")
	var heard_near: int = 0
	var heard_far: int = 0
	for raw: Variant in pants:
		var e: NoiseSystem.Event = raw
		for d: Variant in e.deliveries:
			var listener: int = int(Variants.number(Variants.dict(d)["listener"]))
			heard_near += 1 if listener == near.slot else 0
			heard_far += 1 if listener == far.slot else 0
	var path_near: float = s.run.road_graph.graph.path_cost(Vector2i(floori(stop.x), 1), Vector2i(floori(stop.x) + 8, 1), RoadGraphService.MODE_AIR, 50.0)
	assert_eq(path_near, 8.0)
	# The first panting event comes at the stop, before the listeners joined: count those after.
	assert_eq(heard_near, 3, "the listener 8 tiles off hears every event after it arrived")
	assert_eq(heard_far, 0, "the one 10 tiles off hears none")
