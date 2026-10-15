extends "res://tests/unit/vis/render/render_test.gd"
## UI-02: each of the four close-ups covers the whole screen. With a fully lit mine drawn beneath
## it, the screen is pixel for pixel the same as with no mine at all, while a caption on UI-03's
## layer still shows above it.

const CAPTION: Color = Color(1.0, 0.0, 1.0)


func test_each_close_up_covers_every_world_pixel_and_captions_show() -> void:
	if skip_without_renderer():
		return
	var view: ReceivedView = K.view_with(K.all_lit(0.9))
	var drawn: DrawnSet = K.drawn_from(view)
	var m: CloseupManager = CloseupManager.new()
	add_child_autofree(m)
	var captions: CanvasLayer = CanvasLayer.new()
	captions.layer = CloseupManager.CAPTIONS_LAYER
	var caption: ColorRect = ColorRect.new()
	caption.color = CAPTION
	caption.position = Vector2(860, 900)
	caption.size = Vector2(200, 40)
	captions.add_child(caption)
	add_child_autofree(captions)
	var world: Image = await render(view, drawn, Intents.facing_u16(0.0), 1.0)
	assert_false(K.is_black(world.get_pixelv(K.px(Vector2(20.5, 8.5)))), "the mine is drawn and lit beneath")
	for kind: CloseupKind.Kind in [CloseupKind.Kind.MAP_TABLE, CloseupKind.Kind.POCKET_BOOK, CloseupKind.Kind.MANUAL,
			CloseupKind.Kind.SWITCHBOARD]:
		m.apply({"kind": kind, "seat": 0})
		m.step(1.0)
		wv.visible = true
		var over: Image = await render(view, drawn, Intents.facing_u16(0.0), 1.0)
		wv.visible = false
		var alone: Image = await capture()
		var differ: Array[String] = violations(over, 4, func(p: Vector2i, c: Color) -> bool: return c.is_equal_approx(alone.get_pixelv(p)))
		assert_eq(differ, [] as Array[String], "%s: no world pixel shows through" % CloseupKind.name_of(kind))
		assert_true(over.get_pixel(960, 920).is_equal_approx(CAPTION), "%s: the caption shows above it" % CloseupKind.name_of(kind))
		m.apply({"kind": CloseupKind.Kind.NONE, "seat": 0})
		m.step(1.0)
