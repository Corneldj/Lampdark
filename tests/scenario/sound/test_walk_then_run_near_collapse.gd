extends "res://tests/scenario/kit/scenario_test.gd"
## SND-02: walking past a collapse point 3 tiles away never triggers it; the first running step
## within 6 tiles does. Miners' movement is MNR-01's, so the walker here is moved by the test
## and its steps come from SND-02's periodic emitters at the catalogue rates.

const ROWS: PackedStringArray = [
	"##############################",
	"#a...........................#",
	"#............................#",
	"#............................#",
	"#............................#",
	"##############################",
]


func before_all() -> void:
	assert_true(Tuning.load_server())


func _walk(s: Scenario, entity: int, gait: NoiseTypes.Type, from: Vector2i, to_x: int, ticks_per_tile: int) -> Array[int]:
	var handle: int = s.run.noise.start_periodic(gait, entity)
	var fired_at: Array[int] = []
	var hook: Callable = func(_point: int, _event: int) -> void: fired_at.append(s.run.tick)
	s.run.noise.collapse.collapse_triggered.connect(hook)
	var x: float = from.x + 0.5
	while x < to_x + 0.5:
		s.run.registry.move(entity, Vector2(x, from.y + 0.5))
		s.step()
		x += 1.0 / ticks_per_tile
	s.run.noise.stop_periodic(handle)
	s.run.noise.collapse.collapse_triggered.disconnect(hook)
	return fired_at


func test_walking_past_never_runs_trigger() -> void:
	var s: Scenario = make({"seed": 12, "fixture": FixtureMap.from_ascii(ROWS)})
	s.run.noise.collapse.arm(7, Vector2i(14, 4))
	var walker: SimEntity = s.run.registry.create(WorldIds.EntityKind.MINER, Vector2(1.5, 1.5))
	# Walk (3 tiles/s: a tile every 7 ticks or so) the whole road, passing 3 tiles from the point.
	var walking: Array[int] = _walk(s, walker.id, NoiseTypes.Type.STEP_WALK, Vector2i(1, 1), 28, 7)
	assert_eq(walking, [], "9 np steps never start a creak")
	assert_eq(s.run.noise.event_log.size(), 19, "27 tiles at about 3 tiles/s: 19 steps, one every 0.5 s")
	# Run back towards it: the first step within 6 tiles of path starts the creak.
	var runner: SimEntity = s.run.registry.create(WorldIds.EntityKind.MINER, Vector2(1.5, 1.5))
	var running: Array[int] = _walk(s, runner.id, NoiseTypes.Type.STEP_RUN, Vector2i(1, 1), 14, 4)
	assert_eq(running.size() >= 1, true, "a run brings it down")
	var first: NoiseSystem.Event = null
	for e: NoiseSystem.Event in s.run.noise.event_log:
		if not e.collapses.is_empty():
			first = e
			break
	assert_not_null(first)
	var cost: float = s.run.road_graph.graph.path_cost(first.origins[0], Vector2i(14, 4), RoadGraphService.MODE_AIR, 50.0)
	assert_lte(cost, 6.0, "within 6 tiles by path")
	assert_eq(first.type, NoiseTypes.Type.STEP_RUN)
	var earlier_runs: Array = s.run.noise.event_log.filter(func(e: NoiseSystem.Event) -> bool: return e.type == NoiseTypes.Type.STEP_RUN and e.id < first.id)
	for raw: Variant in earlier_runs:
		var e: NoiseSystem.Event = raw
		assert_gt(s.run.road_graph.graph.path_cost(e.origins[0], Vector2i(14, 4), RoadGraphService.MODE_AIR, 50.0), 6.0,
			"every earlier running step was further than 6 tiles")
