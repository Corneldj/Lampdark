extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-15: a roof fall (HAZ-03's call) erases the trail on exactly the tiles it covers, in the
## vision's trail and the diff log alike.

const H = preload("res://tests/scenario/creatures/stythe_hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_fall_erases_only_its_tiles() -> void:
	var s: Scenario = make({"seed": 1561, "fixture": H.road(), "overrides": H.W.ON})
	var h: H = H.new()
	h.build(s, 40, 37, 95)
	assert_true(h.until_state(&"keep", 1600))
	var before: int = s.run.vision.trails.size()
	var fallen: Array[Vector2i] = [Vector2i(60, 2), Vector2i(61, 2), Vector2i(62, 2), Vector2i(61, 1)]
	s.run.stythe_lair.trail.erase(fallen)
	for t: Vector2i in fallen:
		assert_false(s.run.vision.trails.has(t), "%s erased" % t)
		assert_eq(s.run.diff_log.store.blood_at(t), -1, "and gone from the log")
	assert_eq(s.run.vision.trails.size(), before - 3, "only the three trail tiles it covered")
	assert_true(s.run.vision.trails.has(Vector2i(59, 2)) and s.run.vision.trails.has(Vector2i(63, 2)), "its neighbours kept")
