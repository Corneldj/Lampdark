extends "res://tests/unit/vis/render/render_test.gd"
## VIS-05: every pixel outside the drawn set, the cone or the view samples exactly (0, 0, 0), at every
## Brightness and Lamp Glow setting and with bloom on; and after 60 s in the dark the screen is
## identical to the first second (no adaptation).


func _outside_is_black(img: Image, drawn: DrawnSet, facing: int) -> Array[String]:
	return violations(img, 6, func(p: Vector2i, c: Color) -> bool:
		var w: Vector2 = world_at(p)
		var t: Vector2i = Vector2i(floori(w.x), floori(w.y))
		var inside: bool = drawn.tiles.has(t) and DrawnSet.in_cone(K.MINER, facing, w)
		# The own miner's disc is drawn after the mask: leave it out.
		if w.distance_to(K.MINER) < 0.6:
			return true
		return inside or K.is_black(c))


func test_black_outside_under_every_setting() -> void:
	if skip_without_renderer():
		return
	# Lit everywhere, but the server sent only a patch: the drawn set is that patch.
	var patch: Dictionary = {}
	for y: int in range(4, 13):
		for x: int in range(15, 24):
			patch[Vector2i(x, y)] = 1.0
	var view: ReceivedView = K.view_with(patch)
	var drawn: DrawnSet = K.drawn_from(view)
	for setting: Array in [[1.0, 0.0, 0.0], [2.5, 0.0, 0.0], [0.4, 0.0, 0.0], [1.0, 1.0, 0.0], [1.0, 0.0, 1.0], [3.0, 1.0, 1.0]]:
		wv.brightness = setting[0]
		wv.lamp_glow = setting[1]
		wv.bloom = setting[2]
		var img: Image = await render(view, drawn, 0, 1.0)
		var bad: Array[String] = _outside_is_black(img, drawn, 0)
		assert_eq(bad, [] as Array[String], "brightness %.1f, glow %.1f, bloom %.1f: exact black outside" % setting)
		var inside: Color = img.get_pixelv(K.px(Vector2(20.5, 8.5)))
		assert_false(K.is_black(inside), "and the patch itself is drawn")


func test_no_adaptation_after_a_minute() -> void:
	if skip_without_renderer():
		return
	var view: ReceivedView = K.view_with({})
	var drawn: DrawnSet = K.drawn_from(view)
	var first: Image = await render(view, drawn, 0, 0.0)
	Engine.time_scale = 30.0
	await get_tree().create_timer(60.0).timeout
	Engine.time_scale = 1.0
	var later: Image = await render(view, drawn, 0, 0.0)
	assert_eq(later.get_data(), first.get_data(), "60 s in the dark: the same screen, pixel for pixel")
