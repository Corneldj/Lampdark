extends GutTest
## NET-05's interpolation: entities between the frames either side of the render time; tokens
## appear and vanish at their frames' times; at most 50 ms of extrapolation, then a hold.


func before_all() -> void:
	assert_true(Tuning.load_server())


func _view(entities: Dictionary) -> ReceivedView:
	var v: ReceivedView = ReceivedView.new()
	for token: Variant in entities.keys():
		v.entities[token] = {"level": 1, "size_or_kind": 1, "position": entities[token]}
	return v


func test_between_frames() -> void:
	var b: InterpolationBuffer = InterpolationBuffer.new()
	b.push(10, _view({5: Vector2(0, 0)}))
	b.push(11, _view({5: Vector2(1, 0)}))
	var at: Vector2 = Variants.dict(b.sample(10.25)[5])["position"]
	assert_almost_eq(at.x, 0.25, 1e-6)
	assert_eq(b.sample(9.9).size(), 0, "nothing before the first frame")


func test_tokens_appear_and_vanish_at_their_frames() -> void:
	var b: InterpolationBuffer = InterpolationBuffer.new()
	b.push(10, _view({5: Vector2(0, 0)}))
	b.push(11, _view({5: Vector2(1, 0), 6: Vector2(3, 3)}))
	b.push(12, _view({6: Vector2(3, 3)}))
	assert_false(b.sample(10.9).has(6), "6 appears at its creating frame's time")
	assert_true(b.sample(11.0).has(6))
	assert_true(b.sample(11.9).has(5), "5 is drawn until its removing frame's time")
	assert_false(b.sample(12.0).has(5))


func test_extrapolate_50_ms_then_hold() -> void:
	var b: InterpolationBuffer = InterpolationBuffer.new()
	b.push(10, _view({5: Vector2(0, 0)}))
	b.push(11, _view({5: Vector2(1, 0)}))
	var a: Vector2 = Variants.dict(b.sample(11.5)[5])["position"]
	assert_almost_eq(a.x, 1.5, 1e-6, "extrapolating within 50 ms")
	var c: Vector2 = Variants.dict(b.sample(14.0)[5])["position"]
	assert_almost_eq(c.x, 2.0, 1e-6, "held after 50 ms (one tick)")


func test_render_time_is_100_ms_behind() -> void:
	var clock: ClientClock = ClientClock.new()
	clock.on_frame(99, 0)
	assert_almost_eq(clock.server_tick(0), 100.0, 1e-6)
	assert_almost_eq(clock.shown_tick(0), 98.0, 1e-6, "two ticks, 100 ms, behind")
	assert_almost_eq(clock.shown_tick(25000), 98.5, 1e-6)
