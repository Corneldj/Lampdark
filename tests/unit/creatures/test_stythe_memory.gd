extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-13: it remembers the last 1 + crew count places it sensed unlit miners, each for 900 ticks.

const W = preload("res://tests/unit/creatures/stythe_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_one_plus_crew_places_for_45_s() -> void:
	var s: Scenario = make({"seed": 1221, "fixture": W.road(60), "overrides": W.ON})
	var st: StytheCreature = W.stythe(s, Vector2i(50, 2))
	var crew: Array[MinerHandle] = []
	for i: int in 3:
		crew.append(W.miner(s, "m%d" % i, Vector2i(2 + i * 4, 2)))
	s.step(2)
	assert_eq(s.run.crew.count, 3)
	for i: int in 6:
		st.senses.remember(s.run, Vector2i(40 + i, 2), s.run.crew.count)
	assert_eq(st.senses.memory.size(), 4, "1 + crew count places")
	var oldest: Vector2i = st.senses.memory[0]["tile"]
	assert_eq(oldest, Vector2i(42, 2), "the oldest dropped first")
	var at: int = s.run.tick
	s.step(899)
	st.senses.update(s.run, st)
	assert_eq(st.senses.memory.size(), 4, "kept for 899 ticks")
	s.step(1)
	st.senses.update(s.run, st)
	assert_eq(s.run.tick - at, 900)
	assert_eq(st.senses.memory.size(), 0, "forgotten at 900")
