extends "res://tests/scenario/kit/scenario_test.gd"
## SND-02: the running engine, emitted at full 24 np from the winder and from each gate's inner
## portal, as heard 10 tiles of path beyond the gate: 14 np with the gate open, 2 with it shut.

const ROWS: PackedStringArray = [
	"######################",
	"#w..iG...........L...#",
	"######################",
]


func before_all() -> void:
	assert_true(Tuning.load_server())


func _heard(s: Scenario) -> float:
	var heard: Array[float] = []
	var hook: Callable = func(_listener: int, record: Dictionary, _audit: Dictionary = {}) -> void: heard.append(float(Variants.number(record["remaining_np"])))
	s.run.noise.player_hooks.append(hook)
	var f: FixtureMap = s.fixture
	s.run.noise.emit(NoiseTypes.Type.ENGINE_RUNNING, f.spot("w"), {"origins": [f.spot("w"), f.spot("i")]})
	s.step()
	s.run.noise.player_hooks.erase(hook)
	return heard[0] if heard.size() == 1 else -1.0


func test_the_engine_past_open_and_shut_gates() -> void:
	var s: Scenario = make({"seed": 2, "fixture": FixtureMap.from_ascii(ROWS, {"L": "."})})
	var listener: Vector2i = Vector2i(16, 1)
	s.run.noise.set_player_listener(1, listener)
	assert_eq(s.run.road_graph.graph.path_cost(s.fixture.spot("i"), listener, RoadGraphService.MODE_AIR, 50.0), 22.0,
		"10 tiles of path beyond the gate's inner portal, plus the shut gate's 12")
	assert_eq(_heard(s), 2.0, "beyond the shut gate: 24 - 12 - 10")
	assert_true(s.set_gate(1, true))
	assert_eq(s.run.road_graph.graph.path_cost(s.fixture.spot("i"), listener, RoadGraphService.MODE_AIR, 50.0), 10.0)
	assert_eq(_heard(s), 14.0, "beyond the open gate: 24 - 10")
	assert_eq(s.run.noise.event_log[1].origins.size(), 2, "one event, two origins")
