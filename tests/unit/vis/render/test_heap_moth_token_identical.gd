extends "res://tests/unit/vis/render/render_test.gd"
## VIS-06: a coat heap's token and the sleeping Moth's token (both large and motionless) render
## identically, pixel for pixel; and two miner-sized tokens (a miner, the Stythe) moving at the same
## speed show the same frame.


func _patch(img: Image, at: Vector2, r: int) -> PackedByteArray:
	var c: Vector2i = K.px(at)
	return img.get_region(Rect2i(c - Vector2i(r, r), Vector2i(r * 2, r * 2))).get_data()


func test_heap_and_sleeping_moth() -> void:
	if skip_without_renderer():
		return
	var view: ReceivedView = K.view_with(K.all_lit(0.2))
	view.entities[11] = {"level": 1, "size_or_kind": SeenKind.Size.LARGE_MOTIONLESS, "position": Vector2(20.5, 6.5)}
	view.entities[12] = {"level": 1, "size_or_kind": SeenKind.Size.LARGE_MOTIONLESS, "position": Vector2(20.5, 10.5)}
	var img: Image = await render(view, K.drawn_from(view), Intents.facing_u16(0.0), 1.0)
	var a: PackedByteArray = _patch(img, Vector2(20.5, 6.5), 40)
	var b: PackedByteArray = _patch(img, Vector2(20.5, 10.5), 40)
	assert_eq(a, b, "byte-identical")
	assert_ne(a, _patch(img, Vector2(24.5, 8.5), 40), "and the token is really drawn")


func test_two_tokens_at_one_speed() -> void:
	if skip_without_renderer():
		return
	var view: ReceivedView = K.view_with(K.all_lit(0.2))
	var drawn: DrawnSet = null
	var img: Image = null
	for step: int in 6:
		view.entities[21] = {"level": 1, "size_or_kind": SeenKind.Size.MINER, "position": Vector2(18.5 + step * 0.3, 6.5)}
		view.entities[22] = {"level": 1, "size_or_kind": SeenKind.Size.MINER, "position": Vector2(22.5, 10.5 - step * 0.3)}
		drawn = K.drawn_from(view)
		img = await render(view, drawn, Intents.facing_u16(0.0), 1.0)
	var a: PackedByteArray = _patch(img, Vector2(18.5 + 5 * 0.3, 6.5), 30)
	var b: PackedByteArray = _patch(img, Vector2(22.5, 10.5 - 5 * 0.3), 30)
	assert_eq(a, b, "a miner and the Stythe moving at one speed: the same picture")


## A miner-sized fringe token never shows identity: radially symmetric (mirror-equal), no facing, no
## badge; the same miner at identity shows its facing (mirror-unequal along it).
func test_tokens_never_show_identity() -> void:
	if skip_without_renderer():
		return
	var view: ReceivedView = K.view_with(K.all_lit(0.2))
	view.entities[41] = {"level": 1, "size_or_kind": SeenKind.Size.MINER, "position": Vector2(20.5, 6.5)}
	view.entities[42] = {"level": 2, "size_or_kind": SeenKind.Kind.MINER, "position": Vector2(20.5, 10.5),
		"facing": Intents.facing_u16(0.0), "cues": MinerCues.with_badge(0, 2), "in_hand": 0, "flame": 0}
	var img: Image = await render(view, K.drawn_from(view), Intents.facing_u16(0.0), 1.0)
	var token: Image = img.get_region(Rect2i(K.px(Vector2(20.5, 6.5)) - Vector2i(30, 30), Vector2i(60, 60)))
	var ident: Image = img.get_region(Rect2i(K.px(Vector2(20.5, 10.5)) - Vector2i(30, 30), Vector2i(60, 60)))
	var token_flipped: Image = token.duplicate()
	token_flipped.flip_x()
	var ident_flipped: Image = ident.duplicate()
	ident_flipped.flip_x()
	var token_diff: int = 0
	var ident_diff: int = 0
	# An even crop: the sprite's centre lies on a pixel boundary.
	for y: int in 60:
		for x: int in 60:
			if token.get_pixel(x, y).r8 != token_flipped.get_pixel(x, y).r8:
				token_diff += 1
			if ident.get_pixel(x, y).r8 != ident_flipped.get_pixel(x, y).r8:
				ident_diff += 1
	assert_lt(token_diff, 8, "the token: the same either way, no facing")
	assert_gt(ident_diff, 40, "the identity: its facing shows")
