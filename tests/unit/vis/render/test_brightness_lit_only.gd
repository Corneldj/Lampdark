extends "res://tests/unit/vis/render/render_test.gd"
## VIS-06: Brightness and Lamp Glow at maximum change lit tiles only: the blind area and unsent tiles
## stay (0, 0, 0). (The letterbox bars are the window's clear colour, outside the canvas: VIS-01.)


func test_exposure_touches_lit_tiles_only() -> void:
	if skip_without_renderer():
		return
	var lit: Dictionary = {}
	for y: int in range(5, 12):
		for x: int in range(10, 26):
			lit[Vector2i(x, y)] = 0.5
	var view: ReceivedView = K.view_with(lit)
	var drawn: DrawnSet = K.drawn_from(view)
	var plain: Image = await render(view, drawn, Intents.facing_u16(0.0), 1.0)
	wv.brightness = 2.5
	wv.lamp_glow = 1.0
	var bright: Image = await render(view, drawn, Intents.facing_u16(0.0), 1.0)
	var lit_px: Vector2i = K.px(Vector2(20.5, 8.5))
	assert_gt(bright.get_pixelv(lit_px).r, plain.get_pixelv(lit_px).r + 0.05, "lit tiles brighten")
	for p: Vector2 in [Vector2(12.5, 8.5), Vector2(28.5, 8.5), Vector2(20.5, 14.5), Vector2(5.5, 3.5)]:
		assert_true(K.is_black(bright.get_pixelv(K.px(p))), "%s (blind area or unsent): still pure black" % p)
