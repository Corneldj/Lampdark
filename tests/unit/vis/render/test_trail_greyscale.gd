extends "res://tests/unit/vis/render/render_test.gd"
## VIS-10: a blood trail on a lit tile reads in greyscale apart from bare floor and from chalk white,
## is never pure black, and its streaks run the way the body went: along the trail the pixels are
## steady, across it they alternate between streak and floor.


func _luma(img: Image, p: Vector2i) -> float:
	return img.get_pixelv(p).get_luminance()


func _spread(values: Array[float]) -> float:
	var lo: float = INF
	var hi: float = -INF
	for v: float in values:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return hi - lo


func test_trail_reads_and_shows_its_direction() -> void:
	if skip_without_renderer():
		return
	var view: ReceivedView = K.view_with(K.all_lit(0.6))
	view.tiles[Vector2i(18, 8)] = PackedByteArray([roundi(0.6 * 255.0), 1, 1 | (0 << 3)])  # heading east
	view.tiles[Vector2i(21, 8)] = PackedByteArray([roundi(0.6 * 255.0), 1, 1 | (2 << 3)])  # heading south
	var img: Image = await render(view, K.drawn_from(view), 0, 1.0)
	var tile_px: float = Tuning.f(&"camera.tile_px_at_1080p")
	var floor_l: float = _luma(img, K.px(Vector2(16.5, 8.5)))
	var trail_l: float = _luma(img, K.px(Vector2(18.5, 8.5)))
	gut.p("greyscale: floor %.3f, trail %.3f, chalk white %.3f" % [floor_l, trail_l, Palette.CHALK_WHITE.get_luminance()])
	assert_gt(absf(floor_l - trail_l), 0.08, "apart from bare floor in greyscale")
	assert_gt(absf(Palette.CHALK_WHITE.get_luminance() - trail_l), 0.3, "and far from chalk white")
	assert_false(K.is_black(img.get_pixelv(K.px(Vector2(18.5, 8.5)))), "never pure black")
	for case: Array in [[Vector2(18.5, 8.5), Vector2.RIGHT], [Vector2(21.5, 8.5), Vector2.DOWN]]:
		var centre: Vector2 = case[0]
		var along: Vector2 = case[1]
		var across: Vector2 = Vector2(-along.y, along.x)
		var on_line: Array[float] = []
		var cross_line: Array[float] = []
		for i: int in range(-12, 13):
			on_line.append(_luma(img, K.px(centre) + Vector2i((along * i).round())))
			cross_line.append(_luma(img, K.px(centre) + Vector2i((across * i * tile_px / 32.0).round())))
		assert_lt(_spread(on_line), _spread(cross_line), "streaks run along %s" % along)
