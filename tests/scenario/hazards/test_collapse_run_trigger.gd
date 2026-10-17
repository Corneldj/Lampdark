extends "res://tests/scenario/kit/scenario_test.gd"
## HAZ-03 (Gameplay §12.5, §4.1, §6.1): running is the only gait loud enough to bring a roof down.
## A miner walking the whole room past an armed collapse point 3 tiles off never starts its creak;
## running back, the first running step within 6 tiles of it by path does (and none before it was
## that close).

const W = preload("res://tests/unit/hazards/collapse_world.gd")

## A room five tiles high, the collapse's rubble along its south wall at x 14-16.
const ROOM: PackedStringArray = [
	"##############################",
	"#a...........................#",
	"#............................#",
	"#............................#",
	"#.............RRR............#",
	"##############################",
]


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_walking_past_never_running_does() -> void:
	var s: Scenario = make(W.cfg(3401, ROOM))
	var p: CollapsePoints.Point = W.arm(s)
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"), {"facing_deg": 0.0})
	ann.brain = null
	s.step(2)
	ann.at(s.run.tick).face(0.0).move(0.0, InputRecord.Gait.WALK, 220)
	s.step(230)
	assert_gt(s.run.registry.get_entity(ann.entity_id).position.x, 24.0, "she walked the room")
	assert_gt(W.events_of(s, NoiseTypes.Type.STEP_WALK).size(), 10, "her steps were heard")
	assert_eq(p.state, CollapsePoints.State.STANDING, "walking past 3 tiles off never starts the creak")
	ann.at(s.run.tick).face(180.0).move(180.0, InputRecord.Gait.RUN, 80)
	assert_true(s.run_until(func(_sc: Scenario) -> bool: return p.state == CollapsePoints.State.CREAKING, 100), "a run starts it")
	var first: NoiseSystem.Event = null
	for e: NoiseSystem.Event in s.run.noise.event_log:
		if e.collapses.has(p.id):
			first = e
			break
	assert_not_null(first)
	assert_eq(first.type, NoiseTypes.Type.STEP_RUN, "a running step")
	assert_lte(_path_to(s, first.origins[0], p.rubble), 6.0, "within 6 tiles by path")
	for e: NoiseSystem.Event in W.events_of(s, NoiseTypes.Type.STEP_RUN):
		if e.id < first.id:
			assert_gt(_path_to(s, e.origins[0], p.rubble), 6.0, "every earlier running step was further")


static func _path_to(s: Scenario, from: Vector2i, tiles: Array[Vector2i]) -> float:
	var best: float = INF
	for t: Vector2i in tiles:
		var c: float = s.run.road_graph.graph.path_cost(from, t, RoadGraphService.MODE_AIR, 50.0)
		if c >= 0.0:
			best = minf(best, c)
	return best
