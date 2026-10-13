extends GutTest
## NET-12: percentiles by nearest rank; the client probes' light-to-contents (a token on a newly lit
## tile: its delay; already there: 0; nothing ever: not counted), about-turn tagging and held
## geometry frames, and their cost.


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_percentiles() -> void:
	var v: Array[float] = []
	for i: int in range(1, 101):
		v.append(float(i))
	assert_eq(ProbeMath.percentile(v, 95.0), 95.0)
	assert_eq(ProbeMath.percentile(v, 50.0), 50.0)
	assert_eq(ProbeMath.percentile([7.0] as Array[float], 95.0), 7.0)
	assert_true(is_nan(ProbeMath.percentile([] as Array[float], 95.0)))
	var s: Dictionary = ProbeMath.stats(v)
	assert_eq(int(Variants.number(s["n"])), 100)
	assert_true(ProbeMath.passes(s, 96.0))
	assert_false(ProbeMath.passes(s, 95.0), "p95 under the target, strictly")
	assert_false(ProbeMath.passes(ProbeMath.stats([] as Array[float]), 150.0), "no samples, no pass")


func _view() -> ReceivedView:
	return ReceivedView.new()


func test_light_to_contents() -> void:
	var p: ClientProbes = ClientProbes.new()
	var v: ReceivedView = _view()
	var lamp: Dictionary = {"position": Vector2(10.5, 10.5), "radius": 2.0}
	p.on_frame(1000000, v, lamp, 0)  # facing east, a small pool
	lamp["radius"] = 4.0  # wick up: tiles out to 4 east now lit
	p.on_frame(1010000, v, lamp, 0)
	v.entities[7] = {"level": 3, "position": Vector2(13.5, 10.5), "size_or_kind": 1}
	p.on_frame(1090000, v, lamp, 0)  # its token arrives 80 ms after the light reached its tile
	var s: Dictionary = p.summary()
	assert_eq(int(Variants.number(Variants.dict(s["light"])["n"])), 1)
	assert_almost_eq(float(Variants.number(Variants.dict(s["light"])["p95"])), 80.0, 0.01)
	v.entities[8] = {"level": 1, "position": Vector2(10.5, 12.5), "size_or_kind": 1}  # behind the cone: no sample
	p.on_frame(1100000, v, lamp, 0)
	assert_eq(int(Variants.number(Variants.dict(p.summary()["light"])["n"])), 1)


func test_contents_already_there_count_zero_and_empty_tiles_do_not_count() -> void:
	var p: ClientProbes = ClientProbes.new()
	var v: ReceivedView = _view()
	v.entities[3] = {"level": 3, "position": Vector2(13.5, 10.5), "size_or_kind": 1}  # a margin token, prefetched
	var lamp: Dictionary = {"position": Vector2(10.5, 10.5), "radius": 2.0}
	p.on_frame(1000000, v, lamp, 0)
	lamp["radius"] = 4.0
	p.on_frame(1010000, v, lamp, 0)
	p.on_frame(3000000, v, lamp, 0)  # long after: the empty tiles time out
	var light: Dictionary = p.summary()["light"]
	assert_eq(int(Variants.number(light["n"])), 1, "only the tile with contents")
	assert_eq(float(Variants.number(light["p95"])), 0.0, "drawn at once: the margin had it")


func test_about_turn() -> void:
	var p: ClientProbes = ClientProbes.new()
	var v: ReceivedView = _view()
	var lamp: Dictionary = {"position": Vector2(10.5, 10.5), "radius": 4.0}
	for tile: Vector2i in [Vector2i(9, 10), Vector2i(8, 10), Vector2i(7, 10)]:
		v.geometry[tile] = PackedByteArray([0, 0])  # held floor behind
	p.on_frame(1000000, v, lamp, 0)
	p.on_frame(1010000, v, lamp, 32768)  # an about-turn: west
	v.entities[9] = {"level": 1, "position": Vector2(8.5, 10.5), "size_or_kind": 1}
	p.on_frame(1150000, v, lamp, 32768)
	p.on_frame(2200000, v, lamp, 32768)  # past the window: tiles never held are let go
	var s: Dictionary = p.summary()
	assert_eq(int(Variants.number(s["turns"])), 1)
	assert_almost_eq(float(Variants.number(Variants.dict(s["turn"])["p95"])), 140.0, 0.01, "the reveal behind, tagged as the turn's")
	assert_eq(int(Variants.number(s["turn_held_frames_max"])), 1, "held geometry on the next frame")
	assert_lt(float(Variants.number(s["cost_usec_per_frame"])), 100.0, "under 0.1 ms a frame")


func test_release_keeps_only_summaries() -> void:
	var p: ClientProbes = ClientProbes.new()
	p.keep_samples = false
	var v: ReceivedView = _view()
	v.entities[3] = {"level": 1, "position": Vector2(12.5, 10.5), "size_or_kind": 1}
	var lamp: Dictionary = {"position": Vector2(10.5, 10.5), "radius": 1.0}
	p.on_frame(1000000, v, lamp, 0)
	lamp["radius"] = 4.0
	p.on_frame(1010000, v, lamp, 0)
	assert_eq(p.samples.size(), 0, "no per-tile record")
	assert_eq(int(Variants.number(Variants.dict(p.summary()["light"])["n"])), 1, "but the summary counts it")
