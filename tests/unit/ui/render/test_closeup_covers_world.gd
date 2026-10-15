extends "res://tests/unit/vis/render/render_test.gd"
## UI-02: each of the four close-ups covers the whole screen. With a fully lit mine drawn beneath
## it, the screen is pixel for pixel the same as with no mine at all, while UI-03's captions still
## show above it.


func test_each_close_up_covers_every_world_pixel_and_captions_show() -> void:
	if skip_without_renderer():
		return
	var view: ReceivedView = K.view_with(K.all_lit(0.9))
	var drawn: DrawnSet = K.drawn_from(view)
	var m: CloseupManager = CloseupManager.new()
	add_child_autofree(m)
	var captions: CaptionLayer = CaptionLayer.new()
	add_child_autofree(captions)
	var tap: AudioRecord = AudioRecord.new()
	tap.type = NoiseTypes.Type.HAMMER
	tap.duration_s = 600.0
	captions.system.on_played(tap, Vector2(4, 0), Time.get_ticks_msec() / 1000.0)
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
		var panel: int = 0
		var ink: int = 0
		for y: int in range(940, 1080, 2):
			for x: int in range(760, 1160, 2):
				var c: Color = over.get_pixel(x, y)
				panel += 1 if c.r < 0.3 and c.g < 0.3 else 0
				ink += 1 if c.b > 0.88 and c.r > 0.85 else 0
		assert_gt(panel, 50, "%s: the caption's panel shows above it" % CloseupKind.name_of(kind))
		assert_gt(ink, 5, "%s: and its words" % CloseupKind.name_of(kind))
		m.apply({"kind": CloseupKind.Kind.NONE, "seat": 0})
		m.step(1.0)
