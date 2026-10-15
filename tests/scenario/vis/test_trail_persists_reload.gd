extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-10: a trail survives its cell being evicted and loaded again (the record outlives the cell,
## GEN-13 saves it), and only a roof fall (HAZ-03's erase_trail) takes it away.

const B = preload("res://tests/unit/mnr/belt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _decals_at(s: Scenario, slot: int, t: Vector2i) -> int:
	var f: Dictionary = s.run.vision.frame_for(slot)
	var xs: PackedInt32Array = f["tiles"]["x"]
	var ys: PackedInt32Array = f["tiles"]["y"]
	var decals: PackedByteArray = f["tiles"]["decals"]
	for i: int in xs.size():
		if xs[i] == t.x and ys[i] == t.y:
			return decals[i]
	return -1


func test_trail_kept_through_eviction() -> void:
	var fixture: FixtureMap = B.room()
	var s: Scenario = make({"seed": 1011, "fixture": fixture})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"), {"facing_deg": 0.0})
	ann.brain = null
	B.light(s)
	var t: Vector2i = s.fixture.spot("a") + Vector2i(3, 0)
	s.run.vision.mark_trail(t, 2)
	s.step(2)
	assert_eq(TrailDecal.direction_of(_decals_at(s, ann.slot, t)), 2)
	var cell: Vector2i = WorldCoords.cell_of(t)
	s.run.mine.native.unload(cell)
	s.step(1)
	assert_false(s.run.mine.native.is_loaded(cell), "evicted")
	for file: Dictionary in fixture.cells:
		var data: LbCellData = CellFile.from_dict(file, "fixture")
		if data.get_coord() == cell:
			s.run.mine.native.commit(data)
	s.step(2)
	var bits: int = _decals_at(s, ann.slot, t)
	assert_eq(bits & TileBits.DECAL_BLOOD, TileBits.DECAL_BLOOD, "the trail is back with its cell")
	assert_eq(TrailDecal.direction_of(bits), 2, "with its direction")
	s.run.vision.erase_trail(t)
	s.step(1)
	assert_eq(_decals_at(s, ann.slot, t) & TileBits.DECAL_BLOOD, 0, "only a roof fall erases it")
