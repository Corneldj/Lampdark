extends "res://tests/unit/vis/render/render_test.gd"
## VIS-05: a tile lit to 1.0 by the own lamp in the blind area renders pure black, even though the
## server listed it; the same tile ahead, inside the cone, is drawn.


func test_lit_tile_behind_is_black() -> void:
	if skip_without_renderer():
		return
	var behind: Vector2i = Vector2i(12, 8)
	var ahead: Vector2i = Vector2i(17, 8)
	var view: ReceivedView = K.view_with({behind: 1.0, ahead: 1.0})
	var drawn: DrawnSet = K.drawn_from(view)
	assert_true(drawn.tiles.has(behind), "the server listed it")
	var img: Image = await render(view, drawn, Intents.facing_u16(0.0), 1.0)
	var bad: Array[String] = violations(img, 4, func(p: Vector2i, c: Color) -> bool:
		var w: Vector2 = world_at(p)
		return Vector2i(floori(w.x), floori(w.y)) != behind or K.is_black(c))
	assert_eq(bad, [] as Array[String], "the blind area: pure black where lit to 1.0")
	assert_false(K.is_black(img.get_pixelv(K.px(Vector2(17.5, 8.5)))), "ahead: drawn")
	# Facing west, the two swap.
	img = await render(view, drawn, Intents.facing_u16(180.0), 1.0)
	assert_true(K.is_black(img.get_pixelv(K.px(Vector2(17.5, 8.5)))), "now behind: black")
	assert_false(K.is_black(img.get_pixelv(K.px(Vector2(12.5, 8.5)))), "now ahead: drawn")
