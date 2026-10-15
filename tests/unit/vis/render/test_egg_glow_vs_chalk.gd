extends "res://tests/unit/vis/render/render_test.gd"
## VIS-10: egg-glow renders pale green-white, apart from chalk white and lamp amber in value and hue;
## with the hatch tell it pulses (the drawn brightness swings) and without it holds steady.


func test_egg_glow_apart_from_chalk_and_amber() -> void:
	if skip_without_renderer():
		return
	var view: ReceivedView = K.view_with({})
	var classes: Dictionary = {Vector2i(17, 8): 4, Vector2i(19, 8): 3, Vector2i(21, 8): 1}  # egg-glow, white, amber
	for raw: Variant in classes.keys():
		var t: Vector2i = raw
		view.tiles[t] = PackedByteArray([roundi(0.25 * 255.0), int(Variants.number(classes[raw])), 0])
		view.geometry[t] = PackedByteArray([WorldIds.TileMaterial.FLOOR, 0])
	var img: Image = await render(view, K.drawn_from(view), 0, 1.0)
	var egg: Color = img.get_pixelv(K.px(Vector2(17.5, 8.5)))
	var white: Color = img.get_pixelv(K.px(Vector2(19.5, 8.5)))
	var amber: Color = img.get_pixelv(K.px(Vector2(21.5, 8.5)))
	gut.p("egg %s, white %s, amber %s" % [egg, white, amber])
	assert_gt(egg.g, egg.r, "green-white: green leads")
	assert_gt(absf(egg.h - amber.h), 0.1, "apart from amber in hue")
	assert_gt(absf(egg.s - white.s) + absf(egg.get_luminance() - white.get_luminance()), 0.05, "apart from white in value and hue")


func test_pulse_only_with_the_hatch_tell() -> void:
	if skip_without_renderer():
		return
	var view: ReceivedView = K.view_with({})
	var t: Vector2i = Vector2i(18, 8)
	view.tiles[t] = PackedByteArray([roundi(0.2 * 255.0), 4, 0])
	view.geometry[t] = PackedByteArray([WorldIds.TileMaterial.FLOOR, 0])
	var drawn: DrawnSet = K.drawn_from(view)
	var p: Vector2i = K.px(Vector2(18.5, 8.5))
	var half: float = 0.5 / EggGlowView.pulse_hz()
	wv.show_frame(drawn, view, K.ORIGIN, K.MINER, 0, 1.0, {}, 10.0)
	var a: Color = (await capture()).get_pixelv(p)
	wv.show_frame(drawn, view, K.ORIGIN, K.MINER, 0, 1.0, {}, 10.0 + half)
	var b: Color = (await capture()).get_pixelv(p)
	assert_almost_eq(a.get_luminance(), b.get_luminance(), 0.005, "no hatch tell: steady")
	view.tiles[t] = PackedByteArray([roundi(0.2 * 255.0), 4 | TileBits.COLOUR_HATCH_BIT, 0])
	drawn = K.drawn_from(view)
	wv.show_frame(drawn, view, K.ORIGIN, K.MINER, 0, 1.0, {}, 10.0)
	var c: Color = (await capture()).get_pixelv(p)
	wv.show_frame(drawn, view, K.ORIGIN, K.MINER, 0, 1.0, {}, 10.0 + half)
	var d: Color = (await capture()).get_pixelv(p)
	assert_gt(absf(c.get_luminance() - d.get_luminance()), 0.02, "the hatch tell pulses")
	assert_lt(EggGlowView.pulse_hz(), 3.0, "below 3 Hz")
