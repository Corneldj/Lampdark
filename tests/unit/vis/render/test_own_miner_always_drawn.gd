extends "res://tests/unit/vis/render/render_test.gd"
## VIS-05: the own miner is drawn in total darkness (nothing sent, no light at all), at the minimum
## exposure; in the Dark (BLACK) nothing is drawn, the own miner included.


func test_drawn_in_total_darkness() -> void:
	if skip_without_renderer():
		return
	var view: ReceivedView = K.view_with({})
	var img: Image = await render(view, K.drawn_from(view), Intents.facing_u16(0.0), 0.0)
	var at: Color = img.get_pixelv(K.px(K.MINER))
	assert_false(K.is_black(at), "the own miner reads in total darkness")
	assert_true(K.is_black(img.get_pixelv(K.px(K.MINER + Vector2(3, 0)))), "and nothing else shows")
	wv.set_view_mode(WorldView.Mode.BLACK)
	img = await render(view, K.drawn_from(view), Intents.facing_u16(0.0), 1.0)
	assert_true(K.is_black(img.get_pixelv(K.px(K.MINER))), "the Dark: the own miner hidden too")
