extends "res://tests/unit/vis/render/render_test.gd"
## VIS-05: sampled along both edges, the cone's boundary is a straight line from the miner: no notch,
## no feathering. Everything is lit and drawn; the boundary is found per column and fitted to a line.


func _edge_points(img: Image, upper: bool) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var mp: Vector2 = Vector2(K.px(K.MINER))
	for x: int in range(roundi(mp.x) + 80, img.get_width() - 4, 16):
		# Walk away from the facing line (y = miner's) until the first black pixel.
		var step: int = -1 if upper else 1
		var y: int = roundi(mp.y)
		while y > 0 and y < img.get_height() - 1 and not K.is_black(img.get_pixel(x, y)):
			y += step
		if y > 0 and y < img.get_height() - 1:
			out.append(Vector2(x, y))
	return out


func test_edges_are_straight_lines_from_the_miner() -> void:
	if skip_without_renderer():
		return
	var view: ReceivedView = K.view_with(K.all_lit(0.8))
	var img: Image = await render(view, K.drawn_from(view), Intents.facing_u16(0.0), 1.0)
	var mp: Vector2 = Vector2(K.px(K.MINER))
	var half: float = deg_to_rad(Tuning.f(&"vision.cone_deg") * 0.5)
	for upper: bool in [true, false]:
		var pts: PackedVector2Array = _edge_points(img, upper)
		assert_gt(pts.size(), 5, "edge samples")
		for p: Vector2 in pts:
			var angle: float = absf(atan2(p.y - mp.y, p.x - mp.x))
			# The first black pixel lies just past the edge: within 1.5 px of the ideal line.
			var dist: float = absf(sin(angle - half)) * p.distance_to(mp)
			assert_lt(dist, 1.6, "%s edge at %s: on the straight line" % ["upper" if upper else "lower", p])
