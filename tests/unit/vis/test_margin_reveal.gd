extends GutTest
## VIS-04 on the client: a hidden margin record is never drawn before the predicted own light at
## it reaches 0.12 inside the predicted cone; the predicted pool follows the server's radius.

const EAST: int = 0
const AT: Vector2 = Vector2(10.5, 10.5)


func before_all() -> void:
	assert_true(Tuning.load_server())


func _view(entities: Dictionary) -> ReceivedView:
	var v: ReceivedView = ReceivedView.new()
	v.entities = entities
	return v


func _hidden(position: Vector2, level: int = 3) -> Dictionary:
	return {"level": level, "size_or_kind": LbVision.SIZE_LARGE, "position": position}


func _lamp(radius: float) -> Dictionary:
	return {"position": AT, "radius": radius}


func test_hidden_until_the_light_reaches_it() -> void:
	var view: ReceivedView = _view({1: _hidden(AT + Vector2(4.5, 0.0)), 2: _hidden(AT + Vector2(3.9, 0.0))})
	var r: MarginReveal = MarginReveal.new()
	assert_eq(r.revealed(view, _lamp(4.0), AT, EAST), [2] as Array[int], "R 4: 4.5 tiles out stays hidden; 3.9 shows")
	assert_eq(r.revealed(view, _lamp(5.5), AT, EAST), [1, 2] as Array[int], "wick up (R 5.5): both show")
	assert_eq(r.revealed(view, _lamp(0.0), AT, EAST), [] as Array[int], "no light, nothing shows")


func test_never_outside_the_cone() -> void:
	var view: ReceivedView = _view({1: _hidden(AT + Vector2(-3.0, 0.0)), 2: _hidden(AT + Vector2(0.0, 3.0)),
		3: _hidden(AT + Vector2(2.0, 2.0))})
	var r: MarginReveal = MarginReveal.new()
	assert_eq(r.revealed(view, _lamp(5.5), AT, EAST), [3] as Array[int], "behind and to the side stay hidden; 45 degrees off shows")


func test_a_held_wall_shadows_it() -> void:
	var view: ReceivedView = _view({1: _hidden(AT + Vector2(3.0, 0.0))})
	view.geometry[Vector2i(12, 10)] = PackedByteArray([WorldIds.TileMaterial.ROCK, 0])
	assert_eq(MarginReveal.new().revealed(view, _lamp(5.5), AT, EAST), [] as Array[int])
	view.geometry[Vector2i(12, 10)] = PackedByteArray([WorldIds.TileMaterial.FLOOR, 0])
	assert_eq(MarginReveal.new().revealed(view, _lamp(5.5), AT, EAST), [1] as Array[int])


func test_only_hidden_records_are_judged() -> void:
	var view: ReceivedView = _view({1: _hidden(AT + Vector2(9.0, 0.0), 1), 2: _hidden(AT + Vector2(9.0, 0.0), 2)})
	assert_eq(MarginReveal.new().revealed(view, _lamp(4.0), AT, EAST), [] as Array[int], "seen records are the renderer's already")


func test_property_never_drawn_before_light_reaches_it() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 404
	var r: MarginReveal = MarginReveal.new()
	var cos_half: float = cos(deg_to_rad(Tuning.f(&"vision.cone_deg") * 0.5))
	var shown: int = 0
	for trial: int in 400:
		var facing: int = rng.randi_range(0, 65535)
		var radius: float = rng.randf_range(0.0, 6.0)
		var entities: Dictionary = {}
		for i: int in 12:
			entities[i] = _hidden(AT + Vector2(rng.randf_range(-7.0, 7.0), rng.randf_range(-7.0, 7.0)))
		for token: int in r.revealed(_view(entities), _lamp(radius), AT, facing):
			var p: Vector2 = Variants.dict(entities[token])["position"]
			var light: int = LbLightMath.falloff_milli(AT.distance_to(p), radius, 1.0, Tuning.f(&"light.core_fraction"),
				Tuning.f(&"light.core_value"), Tuning.f(&"light.edge_value"))
			assert_gte(light, 120, "lit to 0.12 at the record")
			var v: Vector2 = p - AT
			var dir: Vector2 = Vector2.from_angle(float(facing) / 65536.0 * TAU)
			assert_true(v.length() <= 0.5 or v.normalized().dot(dir) >= cos_half - 0.0001, "inside the predicted cone")
			shown += 1
	assert_gt(shown, 100, "the property saw reveals")


func test_predicted_pool_follows_the_server_radius() -> void:
	var p: Prediction = Prediction.new()
	var normal: float = Tuning.f(&"lamp.radius_normal")
	assert_almost_eq(Variants.number(p.lamp()["radius"]), normal, 0.0001)
	var still: InputRecord = InputRecord.new()
	p.apply(1, still, HeldGeometry.query({}))
	p.on_server_radius(1, normal * 0.7)
	assert_almost_eq(Variants.number(p.lamp()["radius"]), normal * 0.7, 0.0001, "guttered: the pool shrinks with the server's on the frame")
	p.on_server_radius(99, normal)
	assert_almost_eq(Variants.number(p.lamp()["radius"]), normal * 0.7, 0.0001, "an unknown input's radius is ignored")


func test_wick_step_ramps_over_the_step() -> void:
	var p: Prediction = Prediction.new()
	var normal: float = Tuning.f(&"lamp.radius_normal")
	var up: float = Tuning.f(&"lamp.radius_wick_up")
	var rec: InputRecord = InputRecord.new()
	rec.desired = 4
	var radii: Array[float] = []
	for seq: int in range(1, 7):
		p.apply(seq, rec, HeldGeometry.query({}))
		radii.append(Variants.number(p.lamp()["radius"]))
	assert_lt(radii[0], up, "the pool grows over the step, not at once")
	assert_gt(radii[0], normal - 0.0001)
	for i: int in range(1, radii.size()):
		assert_gte(radii[i], radii[i - 1], "growing")
	assert_almost_eq(radii[p.lamp_step_ticks], up, 0.0001, "at the step's end it is the wick-up radius")
