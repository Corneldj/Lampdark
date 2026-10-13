extends "res://tests/unit/vis/render/render_test.gd"
## VIS-09 drawn: shading darkens a lit tile by level and never to pure black; the dust haze shows on
## lit tiles while the flag is set and leaves the dark black; base camp white is steady from frame to
## frame with a hard edge against the dark.


func test_shading_darkens_but_never_black() -> void:
	if skip_without_renderer():
		return
	var view: ReceivedView = K.view_with(K.all_lit(0.5))
	for level: int in [1, 2, 3]:
		var t: Vector2i = Vector2i(16 + level * 2, 8)
		view.tiles[t] = PackedByteArray([roundi(0.5 * 255.0), 1, level << 6])
	var img: Image = await render(view, K.drawn_from(view), 0, 1.0)
	var plain: Color = img.get_pixelv(K.px(Vector2(16.5, 8.5)))
	var last: float = plain.get_luminance()
	for level: int in [1, 2, 3]:
		var c: Color = img.get_pixelv(K.px(Vector2(16 + level * 2 + 0.5, 8.5)))
		assert_lt(c.get_luminance(), last, "level %d is darker than the one before" % level)
		assert_false(K.is_black(c), "level %d is never pure black" % level)
		last = c.get_luminance()


func test_dust_on_lit_tiles_only() -> void:
	if skip_without_renderer():
		return
	var tiles: Dictionary = {}
	for y: int in range(6, 11):
		for x: int in range(15, 22):
			tiles[Vector2i(x, y)] = 0.6
	var view: ReceivedView = K.view_with(tiles)
	var before: Image = await render(view, K.drawn_from(view), 0, 1.0)
	view.dust = true
	var after: Image = await render(view, K.drawn_from(view), 0, 1.0)
	var a: float = 0.0
	var b: float = 0.0
	for y: int in range(K.px(Vector2(15, 6)).y, K.px(Vector2(22, 11)).y, 4):
		for x: int in range(K.px(Vector2(15, 6)).x, K.px(Vector2(22, 11)).x, 4):
			a += before.get_pixel(x, y).get_luminance()
			b += after.get_pixel(x, y).get_luminance()
	assert_gt(b, a * 1.02, "the haze shows on the lit tiles")
	assert_true(K.is_black(after.get_pixelv(K.px(Vector2(3.5, 3.5)))), "and never in the dark")


func test_camp_white_steady_with_a_hard_edge() -> void:
	if skip_without_renderer():
		return
	var view: ReceivedView = K.view_with({})
	for x: int in range(16, 22):
		view.tiles[Vector2i(x, 8)] = PackedByteArray([230, 3, 0])
		view.geometry[Vector2i(x, 8)] = PackedByteArray([WorldIds.TileMaterial.FLOOR, 0])
	var drawn: DrawnSet = K.drawn_from(view)
	wv.show_frame(drawn, view, K.ORIGIN, K.MINER, 0, 1.0, {}, 1.0)
	var first: Image = await capture()
	wv.show_frame(drawn, view, K.ORIGIN, K.MINER, 0, 1.0, {}, 7.3)
	var later: Image = await capture()
	for x: int in range(16, 22):
		var p: Vector2i = K.px(Vector2(x + 0.5, 8.5))
		assert_eq(first.get_pixelv(p), later.get_pixelv(p), "steady: no flicker at tile %d" % x)
	assert_true(K.is_black(first.get_pixelv(K.px(Vector2(19.5, 9.5)))), "a hard edge: the next row is black")
