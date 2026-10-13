extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-09 end to end: a lure 6-10 tiles off frees the victim, and a bang too close (under 6) or a
## quiet one (under 14 np) does not.

const W = preload("res://tests/scenario/creatures/hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	W.ring(1)


func after_each() -> void:
	super.after_each()
	Tuning.clear_dev_overrides()


func _try(x: int, np: float) -> int:
	var s: Scenario = make({"seed": 90 + x, "fixture": W.road()})
	var r: Array = W.pinned(s)
	var ann: MinerHandle = r[0]
	s.step(2)
	W.bang(s, Vector2i(x, 5), np, 0)
	s.step(3)
	return W.life(s, ann.entity_id)


func test_band() -> void:
	assert_eq(_try(16, 14.0), MinerTransitions.Life.UPRIGHT, "6 tiles: a lure")
	assert_eq(_try(20, 14.0), MinerTransitions.Life.UPRIGHT, "10 tiles: a lure")
	assert_eq(_try(14, 14.0), MinerTransitions.Life.GRABBED, "4 tiles: too close")
	assert_eq(_try(17, 13.0), MinerTransitions.Life.GRABBED, "13 np: too quiet")
