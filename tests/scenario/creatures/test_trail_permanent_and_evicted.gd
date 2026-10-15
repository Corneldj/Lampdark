extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-15 with GEN-13: a drag's trail survives its cells' eviction and return, and a knock-off save
## restored into a fresh run, tile for tile and byte for byte.

const H = preload("res://tests/scenario/creatures/stythe_hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _cell_file(s: Scenario, cell: Vector2i) -> LbCellData:
	for file: Dictionary in s.fixture.cells:
		var data: LbCellData = CellFile.from_dict(file, "trail")
		if data.get_coord() == cell:
			return data
	return null


func test_the_trail_outlasts_eviction_and_a_save() -> void:
	var s: Scenario = make({"seed": 1551, "fixture": H.road(), "overrides": H.W.ON})
	var h: H = H.new()
	h.build(s, 40, 37, 95)
	assert_true(h.until_state(&"keep", 1600))
	var trail: Dictionary = s.run.vision.trails.duplicate()
	assert_gte(trail.size(), 50, "a long trail")
	var cells: Array[Vector2i] = [Vector2i(2, 0), Vector2i(3, 0)]
	var blood_before: Array = []
	for c: Vector2i in cells:
		blood_before.append(s.run.diff_log.store.blood(c))
		s.run.mine.queue_unload(c)
	s.step(1)
	# Forget the evicted cells' trail entirely: only the log can bring it back.
	for t: Variant in trail.keys():
		var tile: Vector2i = t
		if cells.has(WorldCoords.cell_of(tile)):
			s.run.vision.trails.erase(tile)
	for c: Vector2i in cells:
		s.run.mine.queue_commit(_cell_file(s, c))
	s.step(1)
	for t: Variant in trail.keys():
		var want: int = int(Variants.number(trail[t]))
		var got: int = int(Variants.number(s.run.vision.trails.get(t, -1)))
		assert_eq(got, want, "%s back from the log" % t)
	var saved: PackedByteArray = s.run.diff_log.serialise(s.run)
	var b: Scenario = make({"seed": 1551, "fixture": H.road()})
	b.step(2)
	assert_true(b.run.diff_log.deserialise(saved))
	for c: Vector2i in b.run.mine.native.loaded_cells():
		b.run.diff_log.replay(b.run, c)
	assert_eq(b.run.vision.trails, s.run.vision.trails, "resumed: the same trail")
	for i: int in cells.size():
		var was: Array = blood_before[i]
		assert_eq(b.run.diff_log.store.blood(cells[i]), was, "byte for byte in the log")
