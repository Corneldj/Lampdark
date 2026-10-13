extends "res://tests/unit/vis/render/render_test.gd"
## VIS-06 (GDD §14.5): with flash reduction on, a flare's pool reaches full exposure no sooner than
## light.flash_build_s, no frame is pure white, and the 0.1 s muzzle flash draws at half peak for its
## 2 ticks. Off, the pool shows at once.


func _pool(view: ReceivedView, light: float, cls: int) -> void:
	for y: int in range(6, 11):
		for x: int in range(17, 23):
			view.tiles[Vector2i(x, y)] = PackedByteArray([roundi(light * 255.0), cls, 0])
			view.geometry[Vector2i(x, y)] = PackedByteArray([WorldIds.TileMaterial.FLOOR, 0])


func _red_at(view: ReceivedView, t: float) -> float:
	var drawn: DrawnSet = K.drawn_from(view)
	wv.show_frame(drawn, view, K.ORIGIN, K.MINER, Intents.facing_u16(0.0), 1.0, {}, t)
	var img: Image = await capture()
	return img.get_pixelv(K.px(Vector2(20.5, 8.5))).r


func test_flare_builds_over_half_a_second() -> void:
	if skip_without_renderer():
		return
	var view: ReceivedView = K.view_with({})
	_pool(view, 0.05, Palette.CLASS_PALE_AMBER)
	wv.flash.enabled = false
	var full_off: float = await _red_at(view, 0.0)
	_pool(view, 1.0, Palette.CLASS_PALE_AMBER)
	var full: float = await _red_at(view, 0.05)
	assert_gt(full, full_off + 0.3, "off: the flare's pool at once")
	# On: the same jump builds.
	var on: WorldView = WorldView.new()
	add_child_autofree(on)
	wv = on
	wv.flash.enabled = true
	_pool(view, 0.05, Palette.CLASS_PALE_AMBER)
	await _red_at(view, 1.0)
	_pool(view, 1.0, Palette.CLASS_PALE_AMBER)
	var at_0: float = await _red_at(view, 1.05)
	var at_q: float = await _red_at(view, 1.05 + 0.125)
	var at_h: float = await _red_at(view, 1.05 + Tuning.f(&"light.flash_build_s") - 0.05)
	var at_full: float = await _red_at(view, 1.05 + Tuning.f(&"light.flash_build_s") + 0.01)
	assert_almost_eq(at_0, full * Tuning.f(&"light.muzzle_flash_reduced_peak"), 3.0 / 255.0, "half peak at onset (the muzzle flash's 2 ticks)")
	assert_lt(at_0, at_q, "building")
	assert_lt(at_h, full - 1.0 / 255.0, "not yet full before 0.5 s")
	assert_almost_eq(at_full, minf(full, 250.0 / 255.0), 2.0 / 255.0, "full at 0.5 s")
	# No pure white frame, even at the brightest.
	wv.brightness = 3.0
	var img: Image = await capture()
	var max8: int = 0
	for y: int in range(0, img.get_height(), 7):
		for x: int in range(0, img.get_width(), 7):
			var c: Color = img.get_pixel(x, y)
			max8 = maxi(max8, mini(c.r8, mini(c.g8, c.b8)))
	assert_lt(max8, 255, "no pure white")
