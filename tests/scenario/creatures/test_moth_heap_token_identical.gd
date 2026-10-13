extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-03: a sleeping Moth's fringe record is byte-identical to a coat heap's at the same light;
## awake, it is a different (moving) large shape. Nothing of its sleep reaches a client.

const W = preload("res://tests/scenario/creatures/moth_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _tokens(real_moth: bool) -> Dictionary:
	var s: Scenario = make({"seed": 20, "fixture": W.road()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(4, 2), {"facing_deg": 0.0})
	ann.at(0).face(0.0)
	s.run.light.grid.add_spot(0, W.ROOST, 0.2, 0)
	if real_moth:
		W.moth(s)
	else:
		s.run.registry.create(WorldIds.EntityKind.COAT_HEAP, Vector2(W.ROOST) + Vector2(0.5, 0.5))
	s.step(3)
	return Variants.dict(s.run.vision.frame_for(ann.slot)["tokens"])


func test_identical() -> void:
	var heap: Dictionary = _tokens(false)
	var moth: Dictionary = _tokens(true)
	assert_eq(var_to_bytes(moth), var_to_bytes(heap), "byte-identical fringe records")
	var sizes: PackedByteArray = moth["size"]
	assert_eq(sizes, PackedByteArray([LbVision.SIZE_LARGE_MOTIONLESS]))
