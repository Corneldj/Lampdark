extends "res://tests/unit/vis/render/render_test.gd"
## VIS-06: a tile with received light L draws at the exposure for L in its class's colour, over the
## ramp 0.12-1.0, for flame amber and base camp white.


func test_ramp_in_class_colour() -> void:
	if skip_without_renderer():
		return
	var levels: Array[float] = [0.12, 0.25, 0.4, 0.55, 0.7, 0.85, 1.0]
	for cls: int in [1, 3]:
		var view: ReceivedView = K.view_with({})
		for i: int in levels.size():
			var t: Vector2i = Vector2i(16 + i * 2, 8)
			view.tiles[t] = PackedByteArray([roundi(levels[i] * 255.0), cls, 0])
			view.geometry[t] = PackedByteArray([WorldIds.TileMaterial.FLOOR, 0])
		var img: Image = await render(view, K.drawn_from(view), Intents.facing_u16(0.0), 1.0)
		var tint: Color = Palette.class_colour(cls)
		for i: int in levels.size():
			# A tile centre reads its own texel alone (the bilinear weights its neighbours by 0 there).
			var c: Color = img.get_pixelv(K.px(Vector2(16 + i * 2 + 0.5, 8.5)))
			var want: Vector3 = WorldView.FLOOR_ALBEDO * Vector3(tint.r, tint.g, tint.b) * (roundi(levels[i] * 255.0) / 255.0)
			assert_almost_eq(c.r, want.x, 2.5 / 255.0, "class %d, L %.2f: red" % [cls, levels[i]])
			assert_almost_eq(c.g, want.y, 2.5 / 255.0, "class %d, L %.2f: green" % [cls, levels[i]])
			assert_almost_eq(c.b, maxf(want.z, Tuning.f(&"vision.min_drawn_level") / 255.0), 2.5 / 255.0, "class %d, L %.2f: blue" % [cls, levels[i]])
