extends GutTest
## MNR-01's collision: a circle that never overlaps a solid tile, slides along ribs, and bumps
## once per contact.

var p: MinerMotion.Params


func before_all() -> void:
	assert_true(Tuning.load_server())
	p = MinerMotion.Params.from_tuning()


static func _overlap(x: float, y: float, r: float, solid: Dictionary) -> float:
	var worst: float = 0.0
	for raw: Variant in solid.keys():
		var t: Vector2i = raw
		var qx: float = clampf(x, t.x, t.x + 1)
		var qy: float = clampf(y, t.y, t.y + 1)
		var d: float = sqrt((x - qx) * (x - qx) + (y - qy) * (y - qy))
		worst = maxf(worst, r - d)
	return worst


func test_ten_thousand_random_moves_never_overlap() -> void:
	var rng: LbRng = LbRng.from_seed(4242)
	var solid: Dictionary = {}
	for y: int in range(-1, 21):
		for x: int in range(-1, 21):
			if x < 0 or y < 0 or x > 19 or y > 19 or rng.chance_ppm(180000):
				solid[Vector2i(x, y)] = true
	solid.erase(Vector2i(10, 10))
	var is_solid: Callable = func(t: Vector2i) -> bool: return solid.has(t)
	var s: MinerMotion.State = MinerMotion.State.new()
	s.x = 10.5
	s.y = 10.5
	var worst: float = 0.0
	for _i: int in 10000:
		var input: InputRecord = InputRecord.new()
		input.move_dir = rng.range(0, 254)
		input.gait = rng.range(0, 2) as InputRecord.Gait
		s = MinerMotion.step(s, input, MinerMotion.Constraints.new(), 1.0, is_solid, 0.05, p).state
		worst = maxf(worst, _overlap(s.x, s.y, p.body_radius, solid))
	assert_lt(worst, 1e-6, "never overlaps a solid tile (worst " + str(worst) + ")")


func test_sliding_along_a_rib_keeps_the_tangential_component() -> void:
	var is_solid: Callable = func(t: Vector2i) -> bool: return t.x >= 5
	var s: MinerMotion.State = MinerMotion.State.new()
	s.x = 4.6
	s.y = 2.5
	var input: InputRecord = InputRecord.new()
	input.move_dir = roundi(45.0 / 360.0 * InputRecord.DIRECTIONS)  # south-east, into the wall
	input.gait = InputRecord.Gait.WALK
	var d: PackedFloat64Array = MinerMotion.direction(input.move_dir)
	var y0: float = s.y
	for _i: int in 20:
		s = MinerMotion.step(s, input, MinerMotion.Constraints.new(), 1.0, is_solid, 0.05, p).state
	assert_almost_eq(s.x, 5.0 - p.body_radius, 1e-6, "held against the rib")
	assert_almost_eq(s.y - y0, d[1] * 3.0, 1e-6, "the full tangential component: 3.0 x sin 45 per second")


func test_one_bump_per_contact() -> void:
	var is_solid: Callable = func(t: Vector2i) -> bool: return t.x >= 5
	var s: MinerMotion.State = MinerMotion.State.new()
	s.x = 3.5
	s.y = 2.5
	var east: InputRecord = InputRecord.new()
	east.move_dir = 0
	var bumps: int = 0
	for _i: int in 20:
		var r: MinerMotion.Result = MinerMotion.step(s, east, MinerMotion.Constraints.new(), 1.0, is_solid, 0.05, p)
		bumps += r.bumped.size()
		s = r.state
	assert_eq(bumps, 1, "pressing on into the wall is one contact")
	s = MinerMotion.step(s, null, MinerMotion.Constraints.new(), 1.0, is_solid, 0.05, p).state
	var again: MinerMotion.Result = MinerMotion.step(s, east, MinerMotion.Constraints.new(), 1.0, is_solid, 0.05, p)
	assert_eq(again.bumped.size(), 1, "stepping back into it is a new contact")
