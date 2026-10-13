extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-09 with an LFT-10 stub: in the ride's first 20 s the cage's sides are faces; a rider within
## 1.5 tiles of a side is struck, a rider in the deck's middle never is, and nobody after 20 s.

const W = preload("res://tests/scenario/creatures/hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	W.ring(1)


func after_each() -> void:
	super.after_each()
	Tuning.clear_dev_overrides()


## A 5-wide deck (x 12-16, rows 4-6) in the shaft rock; its sides are the rock at x 11 and 17.
func _cage() -> FixtureMap:
	var rows: PackedStringArray = PackedStringArray()
	for y: int in 11:
		rows.append("#".repeat(12) + (".".repeat(5) if y >= 4 and y <= 6 else "#####") + "#".repeat(23))
	return FixtureMap.from_ascii(rows)


func _sides() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y: int in range(4, 7):
		out.append(Vector2i(11, y))
		out.append(Vector2i(17, y))
	return out


func _ride(rider_x: int, window: bool) -> int:
	var s: Scenario = make({"seed": 120 + rider_x, "fixture": _cage()})
	var rider: MinerHandle = s.add_miner("rider", Vector2i(rider_x, 5))
	var t: Tapper = W.tapper(s, Vector2i(14, 9))
	t.follower.stop()
	var sides: Array[Vector2i] = _sides()
	t.hunt.extra_faces = func() -> Array[Vector2i]: return sides if window else [] as Array[Vector2i]
	s.step(3)
	W.talk(s, rider)
	s.step(30)
	return W.life(s, rider.entity_id)


func test_cage() -> void:
	assert_eq(_ride(12, true), MinerTransitions.Life.GRABBED, "beside the cage's side in the first 20 s: struck")
	assert_eq(_ride(14, true), MinerTransitions.Life.UPRIGHT, "the deck's middle: never")
	assert_eq(_ride(12, false), MinerTransitions.Life.UPRIGHT, "after 20 s: nobody")
