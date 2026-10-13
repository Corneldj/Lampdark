extends "res://tests/unit/vis/render/render_test.gd"
## VIS-05 (GDD §14.1): every drawn pixel has at least one channel above 0, even a tile the server
## lists at light 0 and at the lowest brightness: exact black only ever means no data.


func test_drawn_pixels_never_pure_black() -> void:
	if skip_without_renderer():
		return
	var tiles: Dictionary = K.all_lit(0.0)
	var view: ReceivedView = K.view_with(tiles)
	var drawn: DrawnSet = K.drawn_from(view)
	wv.brightness = 0.0
	var img: Image = await render(view, drawn, Intents.facing_u16(0.0), 0.0)
	var floor_8: int = Tuning.i(&"vision.min_drawn_level")
	var bad: Array[String] = violations(img, 5, func(p: Vector2i, c: Color) -> bool:
		var w: Vector2 = world_at(p)
		if not DrawnSet.in_cone(K.MINER, Intents.facing_u16(0.0), w):
			return true
		return maxi(c.r8, maxi(c.g8, c.b8)) >= floor_8 - 1)
	assert_eq(bad, [] as Array[String], "inside the drawn set and the cone: never pure black")
