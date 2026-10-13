extends GutTest
## World coordinates and rings through LbWorld, from the shared vectors (FND-07).

const VECTORS: String = "res://native/tests/golden/coords_vectors.json"

var vectors: Dictionary


func before_all() -> void:
	vectors = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(VECTORS)))
	assert_true(Tuning.load_server(), "tuning loads, so the mirror holds depth.ring_start_tiles")


func after_all() -> void:
	Tuning.clear_dev_overrides()


func _int(value: Variant) -> int:
	return int(Variants.number(value))


func test_negative_tiles_floor_into_negative_cells() -> void:
	assert_eq(WorldCoords.cell_of(Vector2i(-1, 0)), Vector2i(-1, 0))
	assert_eq(WorldCoords.local_of(Vector2i(-1, 0)), Vector2i(19, 0))
	assert_eq(WorldCoords.cell_of(Vector2i(-20, -21)), Vector2i(-1, -2))
	assert_eq(WorldCoords.local_of(Vector2i(-20, -21)), Vector2i(0, 19))
	for raw: Variant in Variants.array(vectors.get("division", [])):
		var c: Dictionary = Variants.dict(raw)
		var tile: int = _int(c["tile"])
		assert_eq(WorldCoords.cell_of(Vector2i(tile, 0)).x, _int(c["cell"]))
		assert_eq(WorldCoords.local_of(Vector2i(0, tile)).y, _int(c["local"]))


func test_round_trip_minus_200_to_200() -> void:
	var failures: int = 0
	for x: int in range(-200, 201):
		for y: int in range(-200, 201, 9):
			var tile: Vector2i = Vector2i(x, y)
			if WorldCoords.tile_of(WorldCoords.cell_of(tile), WorldCoords.local_of(tile)) != tile:
				failures += 1
	assert_eq(failures, 0)


func test_blocks_regions_distances_and_positions() -> void:
	assert_eq(WorldCoords.block_of_cell(Vector2i(-1, 1)), Vector2i(-1, 0))
	assert_eq(WorldCoords.region_of_cell(Vector2i(5, -6)), Vector2i(1, -2))
	assert_eq(WorldCoords.cell_chebyshev(Vector2i.ZERO, Vector2i(3, -4)), 4)
	assert_eq(WorldCoords.cell_manhattan(Vector2i.ZERO, Vector2i(3, -4)), 7)
	assert_eq(WorldCoords.tile_at(Vector2(-0.25, 3.99)), Vector2i(-1, 3))
	assert_eq(WorldCoords.shaft_centre(), Vector2(10, 10))


func test_rings_match_vectors_with_tuned_bounds() -> void:
	var cases: Array = Variants.array(vectors.get("rings", []))
	assert_gt(cases.size(), 100)
	for raw: Variant in cases:
		var c: Dictionary = Variants.dict(raw)
		var tile_xy: Array = Variants.array(c["tile"])
		var tile: Vector2i = Vector2i(_int(tile_xy[0]), _int(tile_xy[1]))
		var expected: int = _int(c["ring"])
		assert_eq(WorldCoords.ring_of_tile(tile), expected, "tile %s at %s" % [tile, c["distance"]])
		assert_eq(WorldCoords.ring_of_point(Vector2(tile) + Vector2(0.5, 0.5)), expected, "centre agrees")
	for raw: Variant in Variants.array(vectors.get("points", [])):
		var c: Dictionary = Variants.dict(raw)
		var xy: Array = Variants.array(c["point"])
		assert_eq(LbWorld.ring_of_point(Variants.number(xy[0]), Variants.number(xy[1])), _int(c["ring"]))


func test_ring_bounds_are_tuning_data() -> void:
	var probe: Vector2i = Vector2i(90, 9)  # centre about 80.5 tiles from the shaft
	assert_eq(WorldCoords.ring_of_tile(probe), 1)
	assert_eq(Tuning.set_dev_override("depth.ring_start_tiles", [90, 200, 400, 700]), [] as Array[String])
	assert_eq(WorldCoords.ring_of_tile(probe), 0, "moving the data moves the boundary")
	Tuning.clear_dev_overrides()
	assert_eq(WorldCoords.ring_of_tile(probe), 1)
