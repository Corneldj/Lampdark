extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-03: a heap of coats and a sleeping Moth at the same fringe light give identical tokens;
## the Moth awake is a different (moving) large shape.

const W = preload("res://tests/scenario/vis/vis_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _token_for(kind: WorldIds.EntityKind, flags: int) -> Dictionary:
	var s: Scenario = make({"seed": 2, "fixture": FixtureMap.from_ascii(PackedStringArray(["##########", "#a.......#", "##########"]))})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.run.light.grid.add_spot(0, Vector2i(5, 1), 0.2, 0)
	s.run.light.grid.add_spot(0, Vector2i(6, 1), 0.2, 0)
	s.run.registry.create(kind, Vector2(6.0, 1.5), flags)
	s.step(2)
	return Variants.dict(s.run.vision.frame_for(ann.slot)["tokens"])


func test_identical_bytes() -> void:
	var heap: Dictionary = _token_for(WorldIds.EntityKind.COAT_HEAP, 0)
	var moth: Dictionary = _token_for(WorldIds.EntityKind.MOTH, SimEntity.FLAG_MOTIONLESS)
	assert_eq(var_to_bytes(heap), var_to_bytes(moth), "byte-identical token entries")
	var sizes: PackedByteArray = heap["size"]
	assert_eq(sizes, PackedByteArray([LbVision.SIZE_LARGE_MOTIONLESS]))
	var awake: Dictionary = _token_for(WorldIds.EntityKind.MOTH, 0)
	var awake_sizes: PackedByteArray = awake["size"]
	assert_eq(awake_sizes, PackedByteArray([LbVision.SIZE_LARGE]))
