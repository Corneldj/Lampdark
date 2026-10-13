extends "res://tests/unit/vis/render/render_test.gd"
## VIS-06 with VIS-05's mask: no light bleeds into an unsent tile. One pixel inside the unsent
## neighbour samples (0, 0, 0); one pixel inside the lit tile at the same edge is at full exposure.


func test_hard_edge_at_unsent_tiles() -> void:
	if skip_without_renderer():
		return
	var lit: Dictionary = {}
	for y: int in range(6, 11):
		for x: int in range(16, 22):
			lit[Vector2i(x, y)] = 1.0
	# A bite: one tile in the middle of the pool is not sent.
	lit.erase(Vector2i(19, 8))
	var view: ReceivedView = K.view_with(lit)
	var img: Image = await render(view, K.drawn_from(view), Intents.facing_u16(0.0), 1.0)
	var px: float = Tuning.f(&"camera.tile_px_at_1080p")
	var edge_x: int = roundi(19.0 * px)
	var row: int = roundi(8.5 * px)
	assert_true(K.is_black(img.get_pixel(edge_x + 1, row)), "one pixel inside the bite: black")
	assert_true(K.is_black(img.get_pixel(edge_x + roundi(px) - 2, row)), "the bite's far side: black")
	var inside: Color = img.get_pixel(edge_x - 2, row)
	var centre: Color = img.get_pixelv(K.px(Vector2(18.5, 8.5)))
	assert_almost_eq(inside.r, centre.r, 2.0 / 255.0, "one pixel inside the lit tile: full exposure, no fade toward the bite")
