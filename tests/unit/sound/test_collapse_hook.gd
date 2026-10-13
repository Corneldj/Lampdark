extends "res://tests/scenario/kit/scenario_test.gd"
## SND-02's collapse hook: 18 np within a path cost of 6 starts a collapse; 17 np, or 18 at 7,
## does not; a firedamp blast reaches 7; a shut door blocks it; a Fan surge does not stop it;
## SND-01's delivery function never calls it; a phone's bell 7 tiles away never brings a roof down.

const ROWS: PackedStringArray = [
	"####################",
	"#a.................#",
	"####################",
	"#b.....D...........#",
	"####################",
]

var s: Scenario
var noise: NoiseSystem
var fired: Array[Array] = []


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	s = make({"seed": 3, "fixture": FixtureMap.from_ascii(ROWS)})
	noise = s.run.noise
	fired.clear()
	noise.collapse.collapse_triggered.connect(func(point: int, event: int) -> void: fired.append([point, event]))
	noise.collapse.arm(1, Vector2i(12, 1))


func _emit_at(type: NoiseTypes.Type, tile: Vector2i, opts: Dictionary = {}) -> int:
	var id: int = noise.emit(type, tile, opts)
	s.step()
	return id


func test_the_threshold_and_the_reach() -> void:
	var id: int = _emit_at(NoiseTypes.Type.STEP_RUN, Vector2i(6, 1))
	assert_eq(fired, [[1, id]], "18 np at path cost 6 triggers")
	fired.clear()
	_emit_at(NoiseTypes.Type.VOICE, Vector2i(6, 1), {"level_np": 17.0})
	assert_eq(fired, [], "17 np does not")
	_emit_at(NoiseTypes.Type.STEP_RUN, Vector2i(5, 1))
	assert_eq(fired, [], "18 np at 7 does not")
	_emit_at(NoiseTypes.Type.PHONE_BELL, Vector2i(5, 1))
	assert_eq(fired, [], "a phone bell 7 tiles by path does not")
	id = _emit_at(NoiseTypes.Type.FIREDAMP_BLAST, Vector2i(5, 1))
	assert_eq(fired, [[1, id]], "a firedamp blast reaches 7")
	fired.clear()
	_emit_at(NoiseTypes.Type.FIREDAMP_BLAST, Vector2i(4, 1))
	assert_eq(fired, [], "but not 8")
	var logged: NoiseSystem.Event = noise.event_log[noise.event_log.size() - 2]
	assert_eq(logged.collapses, PackedInt64Array([1]), "the run record notes what it brought down")


func test_a_shut_door_blocks_it() -> void:
	noise.collapse.arm(2, Vector2i(10, 3))
	_emit_at(NoiseTypes.Type.SHOT, Vector2i(5, 3))
	assert_eq(fired.filter(func(f: Array) -> bool: return f[0] == 2), [], "five tiles away, but behind a shut door")
	assert_true(s.set_gate(1, true))
	var id: int = _emit_at(NoiseTypes.Type.SHOT, Vector2i(5, 3))
	assert_true(fired.has([2, id]), "with the door open it falls")


func test_a_fan_surge_does_not_stop_it() -> void:
	noise.creature_filter = func(event: NoiseSystem.Event, _d: Dictionary) -> bool: return event.level_np >= 22.0
	var id: int = _emit_at(NoiseTypes.Type.STEP_RUN, Vector2i(7, 1))
	assert_eq(fired, [[1, id]], "the roof is not a creature")


func test_delivery_and_illusions_never_call_it() -> void:
	var delivered: Dictionary = s.run.road_graph.graph.deliver(Vector2i(10, 1), 40.0, Vector2i(11, 1), RoadGraphService.MODE_AIR, 0.0, 1.0, 9)
	assert_false(delivered.is_empty(), "a direct delivery (how illusions reach their target) still arrives")
	s.step(2)
	assert_eq(fired, [])
	assert_eq(noise.event_log.size(), 0, "and is no event")


func test_disarmed_points_stay_up() -> void:
	noise.collapse.disarm(1)
	_emit_at(NoiseTypes.Type.SHOT, Vector2i(11, 1))
	assert_eq(fired, [])
