extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-09's taps: every 40-80 ticks, 3 distinct usable faces within 15 tiles (10 in Search), none
## within 3 tiles of its true face, as a rock-tap the Tapper does not hear; dust only on lit faces.

const W = preload("res://tests/scenario/creatures/hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_points() -> void:
	var s: Scenario = make({"seed": 30, "fixture": W.road()})
	var t: Tapper = W.tapper(s, Vector2i(20, 8))
	t.follower.stop()
	s.step(2)
	for i: int in 200:
		var radius: float = 15.0 if i % 2 == 0 else 10.0
		var pts: Array[Vector2i] = t.hunt.taps.pick(s.run, t, radius)
		assert_eq(pts.size(), 3)
		var seen: Dictionary = {}
		for p: Vector2i in pts:
			assert_false(seen.has(p), "distinct")
			seen[p] = true
			assert_true(s.run.mine.native.tapper_face_usable(p), "a usable face")
			assert_gte(Vector2(p).distance_to(Vector2(t.tile(s.run))), 3.0, "never within 3 tiles of its true face")
			assert_lte(TapperStrike.square_distance(t.position(s.run), p), radius + 1e-6, "within range")


func test_interval_and_dust() -> void:
	var s: Scenario = make({"seed": 31, "fixture": W.road()})
	var t: Tapper = W.tapper(s, Vector2i(20, 8))
	t.follower.stop()
	var lit: Array = []
	for x: int in range(14, 20):
		lit.append(Vector2i(x, 5))
	s.run.light.grid.add_area("emergency", 3, 0, 0.6, lit)
	s.step(2)
	var ticks: Array[int] = []
	var dust_ok: Array[bool] = [true]
	t.tapped.connect(func(points: Array[Vector2i], dusted: Array[Vector2i]) -> void:
		ticks.append(s.run.tick)
		for p: Vector2i in points:
			var should: bool = p.x >= 14 and p.x <= 19
			if dusted.has(p) != should:
				dust_ok[0] = false)
	for i: int in 800:
		t.hunt.taps.tick(s.run, t, 15.0)
		s.run.tick += 1
	assert_gt(ticks.size(), 8)
	for i: int in range(1, ticks.size()):
		assert_between(ticks[i] - ticks[i - 1], 40, 80, "2-4 s between taps")
	assert_true(dust_ok[0], "dust exactly on the faces beside lit floor")
