extends "res://tests/unit/vis/render/render_test.gd"
## VIS-10: a pool with a bite out of it renders a hard notch: every pixel in a bitten tile is
## (0, 0, 0), right up to the tile's edge, and the lit tile beside it keeps its own colour with no
## gradient across the boundary. The client only finds the tiles missing; nothing flags them.


func test_the_notch_is_hard_and_pure_black() -> void:
	if skip_without_renderer():
		return
	var lit: Dictionary = {}
	for y: int in range(4, 13):
		for x: int in range(15, 24):
			lit[Vector2i(x, y)] = 0.5
	for y: int in range(7, 10):
		for x: int in range(19, 22):
			lit.erase(Vector2i(x, y))  # the bite: the 3x3 block round the Stythe at (20, 8)
	var view: ReceivedView = K.view_with(lit)
	var img: Image = await render(view, K.drawn_from(view), 0, 1.0)
	var tile_px: int = roundi(Tuning.f(&"camera.tile_px_at_1080p"))
	for y: int in range(7, 10):
		for x: int in range(19, 22):
			var corner: Vector2i = K.px(Vector2(x, y))
			for dy: int in [0, tile_px / 2, tile_px - 1]:
				for dx: int in [0, tile_px / 2, tile_px - 1]:
					assert_true(K.is_black(img.get_pixelv(corner + Vector2i(dx, dy))), "tile (%d, %d) is pure black" % [x, y])
	# The tile left of the notch: its pixels next to the edge match its own centre (no gradient).
	var centre: Color = img.get_pixelv(K.px(Vector2(18.5, 8.5)))
	var edge: Color = img.get_pixelv(K.px(Vector2(19.0, 8.5)) - Vector2i(2, 0))
	assert_false(K.is_black(centre))
	assert_almost_eq(edge.get_luminance(), centre.get_luminance(), 0.02, "no gradient into the notch")
