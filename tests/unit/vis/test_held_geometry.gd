extends GutTest
## VIS-05: held geometry is the tile layout received for cells within 2 (Chebyshev, in cells) of
## the miner's last acknowledged position, never the predicted one; no light, no entities; dropped at
## once beyond. It is drawn only while in the drawn set.

const CELL: int = WorldIds.CELL_TILES


func before_all() -> void:
	assert_true(Tuning.load_server())


func _view(own: Vector2) -> ReceivedView:
	var v: ReceivedView = ReceivedView.new()
	v.own["position"] = own
	for cx: int in range(-4, 5):
		v.geometry[Vector2i(cx * CELL + 1, 1)] = PackedByteArray([WorldIds.TileMaterial.ROCK, 0])
	return v


func test_within_two_cells_of_the_acknowledged_position() -> void:
	var v: ReceivedView = _view(Vector2(0.5, 0.5))
	var held: Dictionary = HeldGeometryCache.tiles(v)
	for cx: int in range(-4, 5):
		assert_eq(held.has(Vector2i(cx * CELL + 1, 1)), absi(cx) <= 2, "cell %d" % cx)
	# NET-04's rule, as the decoder applies it with the server's position, drops the same cells.
	v.apply_held_rule(Tuning.i(&"vision.held_geometry_cells"))
	assert_eq(v.geometry.size(), 5)


func test_follows_the_acknowledged_position_not_the_predicted() -> void:
	# The view's own position is the server's; a prediction a cell ahead changes nothing held.
	var v: ReceivedView = _view(Vector2(0.5, 0.5))
	var before: Array = HeldGeometryCache.tiles(v).keys()
	var drawn: DrawnSet = DrawnSet.new()
	drawn.build(v, {"position": Vector2(3.0 * CELL, 0.5), "facing": 0, "lamp": {"position": Vector2(3.0 * CELL, 0.5), "radius": 4.0}}, 0, -1)
	var after: Array = HeldGeometryCache.tiles(v).keys()
	before.sort()
	after.sort()
	assert_eq(after, before)


func test_holds_no_light_and_draws_nothing_by_itself() -> void:
	var v: ReceivedView = _view(Vector2(0.5, 0.5))
	var held: Dictionary = HeldGeometryCache.tiles(v)
	for raw: Variant in held.values():
		var g: PackedByteArray = raw
		assert_eq(g.size(), 2, "material and state only")
	var drawn: DrawnSet = DrawnSet.new()
	drawn.build(v, {"position": Vector2(0.5, 0.5), "facing": 0, "lamp": {}}, 0, -1)
	assert_eq(drawn.tiles.size(), 0, "held walls are never drawn outside the drawn set")
