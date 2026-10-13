extends GutTest
## SND-03 (§6.10): a diffuse tell plays from its wall points, or, with none, from three emitters 120
## degrees apart at noise.diffuse_emitter_distance_tiles from the listener at a random rotation; its
## caption carries no direction. No geometry is revealed: the emitters' mean is the listener.


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_three_emitters_around_the_listener() -> void:
	var p: EventPlayer = EventPlayer.new()
	add_child_autofree(p)
	p.listener = Vector2(10, 5)
	var r: AudioRecord = AudioRecord.new()
	r.type = LocalSounds.Type.MOTH_STIR
	r.flags = AudioRecord.DIFFUSE
	r.apparent = Vector2(40, 40)
	var e: Array[Vector2] = p.emitters(r, 17)
	assert_eq(e.size(), Tuning.i(&"noise.diffuse_emitter_count"))
	var mean: Vector2 = Vector2.ZERO
	for q: Vector2 in e:
		assert_almost_eq(q.distance_to(p.listener), Tuning.f(&"noise.diffuse_emitter_distance_tiles"), 1e-4)
		mean += q
	mean /= e.size()
	assert_almost_eq(mean.distance_to(p.listener), 0.0, 1e-4, "near, never where")
	for i: int in e.size():
		var a: float = (e[i] - p.listener).angle_to(e[(i + 1) % e.size()] - p.listener)
		assert_almost_eq(absf(a), TAU / 3.0, 1e-3, "120 degrees apart")
	assert_ne(p.emitters(r, 18), e, "a fresh rotation per event")


func test_points_when_sent() -> void:
	var p: EventPlayer = EventPlayer.new()
	add_child_autofree(p)
	var r: AudioRecord = AudioRecord.new()
	r.flags = AudioRecord.DIFFUSE
	r.points = [Vector2(1, 1), Vector2(4, 2), Vector2(2, 6)] as Array[Vector2]
	assert_eq(p.emitters(r, 1), r.points, "the emitter's own wall points")


func test_caption_without_direction() -> void:
	var p: EventPlayer = EventPlayer.new()
	add_child_autofree(p)
	var caps: Array = []
	p.caption.connect(func(t: int, d: Variant) -> void: caps.append([t, d]))
	var r: AudioRecord = AudioRecord.new()
	r.type = LocalSounds.Type.MOTH_STIR
	r.flags = AudioRecord.DIFFUSE
	r.points = [Vector2(1, 1), Vector2(4, 2), Vector2(2, 6)] as Array[Vector2]
	p.play(r, 3)
	assert_eq(p.voices.size(), 3, "three emitters")
	assert_eq(caps, [[LocalSounds.Type.MOTH_STIR, null]], "no direction")
