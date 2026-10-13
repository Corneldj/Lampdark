extends "res://tests/unit/vis/render/render_test.gd"
## VIS-06: the six cap badges are distinguishable in a greyscale render by pattern alone: each badge's
## pixels are reduced to greyscale and thresholded at the disc's own mid-tone (removing its colour's
## value), and every pair of the resulting pattern masks differs.


func _mask(img: Image, at: Vector2) -> PackedByteArray:
	var c: Vector2i = K.px(at)
	var r: int = 8
	var lum: Array[float] = []
	var lo: float = 1.0
	var hi: float = 0.0
	for y: int in range(-r, r + 1):
		for x: int in range(-r, r + 1):
			var p: Color = img.get_pixel(c.x + x, c.y + y)
			var l: float = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b
			lum.append(l)
			if x * x + y * y <= (r - 1) * (r - 1):
				lo = minf(lo, l)
				hi = maxf(hi, l)
	var out: PackedByteArray = PackedByteArray()
	var mid: float = (lo + hi) * 0.5
	var i: int = 0
	for y: int in range(-r, r + 1):
		for x: int in range(-r, r + 1):
			out.append(1 if (x * x + y * y <= (r - 1) * (r - 1) and hi - lo > 0.04 and lum[i] < mid) else 0)
			i += 1
	return out


func test_six_patterns() -> void:
	if skip_without_renderer():
		return
	var view: ReceivedView = K.view_with(K.all_lit(0.6))
	var spots: Array[Vector2] = []
	for b: int in 6:
		var at: Vector2 = Vector2(17.5 + (b % 3) * 3.0, 6.5 + (b / 3) * 4.0)
		spots.append(at)
		view.entities[30 + b] = {"level": 2, "size_or_kind": SeenKind.Kind.MINER, "position": at, "facing": Intents.facing_u16(90.0),
			"cues": MinerCues.with_badge(0, b), "in_hand": 0, "flame": 0}
	var img: Image = await render(view, K.drawn_from(view), Intents.facing_u16(0.0), 1.0)
	var masks: Array[PackedByteArray] = []
	for at: Vector2 in spots:
		masks.append(_mask(img, at))
	for i: int in 6:
		for j: int in range(i + 1, 6):
			var diff: int = 0
			for k: int in masks[i].size():
				if masks[i][k] != masks[j][k]:
					diff += 1
			assert_gt(diff, 6, "%s vs %s: told apart by pattern alone" % [Palette.BADGE_PATTERNS[i], Palette.BADGE_PATTERNS[j]])
