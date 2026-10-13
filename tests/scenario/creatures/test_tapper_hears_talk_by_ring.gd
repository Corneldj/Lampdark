extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-08 end to end: a Tapper in the rock hears a miner's talk within its own ring's reach (8
## tiles in ring 1, 12.8 in ring 4), as heat on the wall nearest where it seemed to come from.

const T = preload("res://tests/scenario/creatures/tapper_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_each() -> void:
	super.after_each()
	Tuning.clear_dev_overrides()


func _heard(ring: int, tiles: int) -> bool:
	var bounds: Array = [1000000, 1000001, 1000002, 1000003]
	for i: int in ring:
		bounds[i] = 1 + i
	Tuning.set_dev_override("depth.ring_start_tiles", bounds)
	var s: Scenario = make({"seed": 10 + ring, "fixture": T.road()})
	var t: Tapper = T.tapper(s, Vector2i(1, 1))
	t.follower.stop()
	s.step(1)
	T.voice(s, tiles, Tuning.f(&"voice.talk_np"))
	s.step(2)
	return not t.heat.is_cold()


func test_by_ring() -> void:
	assert_true(_heard(1, 8), "ring 1: talk at 8")
	assert_false(_heard(1, 9), "ring 1: not at 9")
	assert_true(_heard(4, 12), "ring 4: talk at 12")
	assert_false(_heard(4, 13), "ring 4: not at 13")
