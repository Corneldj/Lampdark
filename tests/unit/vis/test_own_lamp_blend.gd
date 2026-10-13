extends GutTest
## VIS-06: display = clamp(server_total - server_own + predicted_own, 0, 1). The predicted pool shows
## at once (a wick step up draws the larger pool, a shutter closing darkens it); once the server's
## own block confirms it, no tile moves by more than one quantisation step. Only drawn tiles blend.


func before_all() -> void:
	assert_true(Tuning.load_server())


## A server frame of the own lamp at `radius`: every tile its pool reaches at 0.12 or more is seen.
func _server_view(at: Vector2, radius: float) -> ReceivedView:
	var v: ReceivedView = ReceivedView.new()
	v.own["position"] = at
	v.own["lamp_radius"] = radius
	for y: int in range(-8, 9):
		for x: int in range(-8, 9):
			var t: Vector2i = Vector2i(floori(at.x) + x, floori(at.y) + y)
			v.geometry[t] = PackedByteArray([WorldIds.TileMaterial.FLOOR, 0])
			var l: float = OwnLampBlend.own_light(v, {"position": at, "radius": radius}, Vector2(t) + Vector2(0.5, 0.5))
			if l >= Tuning.f(&"vision.seen_light_min"):
				v.tiles[t] = PackedByteArray([roundi(l * 255.0), 1, 0])
	return v


func test_wick_up_draws_the_larger_pool_at_once() -> void:
	var at: Vector2 = Vector2(20.5, 10.5)
	var normal: float = LampRules.hand_radius(2)
	var up: float = LampRules.hand_radius(4)
	var v: ReceivedView = _server_view(at, normal)
	var predicted: Dictionary = {"position": at, "facing": 0, "lamp": {"position": at, "radius": up}}
	var d: DrawnSet = DrawnSet.new()
	d.build(v, predicted, 0, -1)
	var lights: Dictionary = OwnLampBlend.lights(d, v, {"position": at, "radius": normal}, {"position": at, "radius": up})
	var reach_before: int = 0
	var reach_now: int = 0
	for raw: Variant in lights.keys():
		var t: Vector2i = raw
		var dx: int = absi(t.x - floori(at.x))
		if t.y == floori(at.y) and float(Variants.number(lights[raw])) >= 0.12:
			reach_now = maxi(reach_now, dx)
			if v.tiles.has(t):
				reach_before = maxi(reach_before, dx)
	assert_gt(reach_now, reach_before, "the larger pool before the server confirms")
	# The server confirms: its frame at the new radius. Nothing moves by more than a step.
	var confirmed: ReceivedView = _server_view(at, up)
	var d2: DrawnSet = DrawnSet.new()
	d2.build(confirmed, predicted, 0, -1)
	var after: Dictionary = OwnLampBlend.lights(d2, confirmed, {"position": at, "radius": up}, {"position": at, "radius": up})
	for raw: Variant in lights.keys():
		if after.has(raw):
			assert_lte(absf(float(Variants.number(after[raw])) - float(Variants.number(lights[raw]))), 1.0 / 255.0 + 1e-6,
				"%s within one quantisation step" % raw)


func test_shutter_darkens_at_once() -> void:
	var at: Vector2 = Vector2(5.5, 5.5)
	var v: ReceivedView = _server_view(at, 4.0)
	var d: DrawnSet = DrawnSet.new()
	d.build(v, {"position": at, "facing": 0, "lamp": {}}, 0, -1)
	var lights: Dictionary = OwnLampBlend.lights(d, v, {"position": at, "radius": 4.0}, {})
	for raw: Variant in lights.keys():
		assert_almost_eq(float(Variants.number(lights[raw])), 0.0, 1.0 / 255.0 + 1e-6, "shuttered: the own pool gone from %s" % raw)


func test_only_drawn_tiles() -> void:
	var at: Vector2 = Vector2(5.5, 5.5)
	var v: ReceivedView = _server_view(at, 4.0)
	var d: DrawnSet = DrawnSet.new()
	d.build(v, {"position": at, "facing": 0, "lamp": {"position": at, "radius": 4.0}}, 0, -1)
	var lights: Dictionary = OwnLampBlend.lights(d, v, {"position": at, "radius": 4.0}, {"position": at, "radius": 8.0})
	for raw: Variant in lights.keys():
		assert_true(d.tiles.has(raw), "%s is drawn" % raw)
