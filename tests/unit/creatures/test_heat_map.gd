extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-08's heat map: heat at the usable face nearest the apparent position, weighted energy x
## duration, kept for exactly the window at each crew count, hottest face by summed heat.

const T = preload("res://tests/scenario/creatures/tapper_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_window_by_crew() -> void:
	for pair: Array in [[1, 90], [2, 90], [3, 105], [4, 120], [5, 135]]:
		var crew: int = pair[0]
		var seconds: int = pair[1]
		assert_eq(HeatMap.window_ticks(crew), seconds * 20, "crew %d" % crew)


func test_heat_and_pruning() -> void:
	var s: Scenario = make({"seed": 1, "fixture": T.road()})
	var nav: CreatureNav = s.run.creatures.nav
	var m: HeatMap = HeatMap.new()
	var face: Vector2i = m.add(s.run, nav, Vector2(10.5, 2.4), 8.0, 0.5)
	assert_eq(face, Vector2i(10, 1), "the usable face nearest the apparent position")
	assert_almost_eq(m.heat_of(Vector2i(10, 1)), 4.0, 1e-9, "energy x duration")
	m.add(s.run, nav, Vector2(30.5, 2.6), 6.0, 2.0)
	var hot: Vector2i = m.hottest()
	assert_eq(hot, Vector2i(30, 3), "the hottest face")
	for crew: int in [1, 3, 5]:
		var k: HeatMap = HeatMap.new()
		k.add(s.run, nav, Vector2(10.5, 2.4), 8.0, 0.5)
		var start: int = s.run.tick
		var window: int = HeatMap.window_ticks(crew)
		s.run.tick = start + window - 1
		k.prune(s.run, crew)
		assert_false(k.is_cold(), "crew %d: kept to the last tick of the window" % crew)
		s.run.tick = start + window
		k.prune(s.run, crew)
		assert_true(k.is_cold(), "crew %d: gone after exactly the window" % crew)
		s.run.tick = start
