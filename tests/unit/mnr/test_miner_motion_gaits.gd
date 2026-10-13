extends GutTest
## MNR-01's gaits: fixed speeds reached in the tick, wounds and modifiers that multiply, instant
## facing and its lock, and the constraint stubs.

var p: MinerMotion.Params
var open: Callable = func(_t: Vector2i) -> bool: return false


func before_all() -> void:
	assert_true(Tuning.load_server())
	p = MinerMotion.Params.from_tuning()


func _rec(dir_deg: float, gait: InputRecord.Gait, facing: int = 0) -> InputRecord:
	var r: InputRecord = InputRecord.new()
	r.move_dir = posmod(roundi(dir_deg / 360.0 * InputRecord.DIRECTIONS), InputRecord.DIRECTIONS)
	r.gait = gait
	r.facing = facing
	return r


## Tiles covered in one second of ticks.
func _speed(input: InputRecord, factor: float = 1.0, c: MinerMotion.Constraints = MinerMotion.Constraints.new()) -> float:
	var s: MinerMotion.State = MinerMotion.State.new()
	for _i: int in 20:
		s = MinerMotion.step(s, input, c, factor, open, 0.05, p).state
	return sqrt(s.x * s.x + s.y * s.y)


func test_gait_speeds_reached_in_the_tick() -> void:
	assert_almost_eq(_speed(_rec(0.0, InputRecord.Gait.CROUCH)), 1.5, 1e-9)
	assert_almost_eq(_speed(_rec(0.0, InputRecord.Gait.WALK)), 3.0, 1e-9)
	assert_almost_eq(_speed(_rec(0.0, InputRecord.Gait.RUN)), 5.5, 1e-9)
	var first: MinerMotion.Result = MinerMotion.step(MinerMotion.State.new(), _rec(0.0, InputRecord.Gait.WALK), MinerMotion.Constraints.new(), 1.0, open, 0.05, p)
	assert_almost_eq(first.state.speed, 3.0, 1e-9, "full speed in the first tick: no ramp")
	var stop: MinerMotion.Result = MinerMotion.step(first.state, null, MinerMotion.Constraints.new(), 1.0, open, 0.05, p)
	assert_eq(stop.state.speed, 0.0, "and none the tick it stops")


func test_diagonals_and_deflection() -> void:
	assert_almost_eq(_speed(_rec(45.0, InputRecord.Gait.WALK)), 3.0, 1e-9, "diagonals are normalised")
	assert_almost_eq(_speed(_rec(200.0, InputRecord.Gait.RUN)), 5.5, 1e-9)
	# The record carries a direction and a gait, never a stick magnitude: half deflection walks
	# at the same 3.0 tiles/s as full deflection.
	var fields: PackedStringArray = PackedStringArray()
	for prop: Dictionary in InputRecord.new().get_property_list():
		fields.append(str(prop["name"]))
	for magnitude: String in ["magnitude", "deflection", "strength", "speed"]:
		assert_false(fields.has(magnitude), "no %s field" % magnitude)


func test_wounds_and_modifiers_multiply() -> void:
	var mods: SpeedModifiers = SpeedModifiers.new()
	mods.set_wound(true)
	assert_almost_eq(_speed(_rec(0.0, InputRecord.Gait.CROUCH), mods.factor()), 1.2, 1e-9)
	assert_almost_eq(_speed(_rec(0.0, InputRecord.Gait.WALK), mods.factor()), 2.4, 1e-9)
	assert_almost_eq(_speed(_rec(0.0, InputRecord.Gait.RUN), mods.factor()), 4.4, 1e-9)
	mods.set_wound(true)  # a trap wound on top of Hurt: one slot, never x0.64
	assert_almost_eq(_speed(_rec(0.0, InputRecord.Gait.WALK), mods.factor()), 2.4, 1e-9)
	mods.set_modifier(&"test_mud", 0.5, 12.0)
	assert_almost_eq(_speed(_rec(0.0, InputRecord.Gait.WALK), mods.factor()), 1.2, 1e-9, "3.0 x 0.8 x 0.5")
	mods.clear(&"test_mud")
	assert_almost_eq(_speed(_rec(0.0, InputRecord.Gait.WALK), mods.factor()), 2.4, 1e-9)


func test_facing_is_instant_unless_locked() -> void:
	var s: MinerMotion.State = MinerMotion.State.new()
	s = MinerMotion.step(s, _rec(0.0, InputRecord.Gait.WALK, 20000), MinerMotion.Constraints.new(), 1.0, open, 0.05, p).state
	assert_eq(s.facing, 20000, "the same tick")
	var lock: MinerMotion.Constraints = MinerMotion.Constraints.new()
	lock.facing_lock = true
	s = MinerMotion.step(s, _rec(0.0, InputRecord.Gait.WALK, 40000), lock, 1.0, open, 0.05, p).state
	assert_eq(s.facing, 20000, "locked: facing input ignored")


func test_constraint_stubs() -> void:
	var walk_only: MinerMotion.Constraints = MinerMotion.Constraints.new()
	walk_only.walk_only = true
	assert_almost_eq(_speed(_rec(0.0, InputRecord.Gait.RUN), 1.0, walk_only), 3.0, 1e-9, "walk-only prevents running")
	var tired: MinerMotion.Constraints = MinerMotion.Constraints.new()
	tired.run_allowed = false
	assert_almost_eq(_speed(_rec(0.0, InputRecord.Gait.RUN), 1.0, tired), 3.0, 1e-9)
	var carry: MinerMotion.Constraints = MinerMotion.Constraints.new()
	carry.fixed_speed = 1.5
	assert_almost_eq(_speed(_rec(0.0, InputRecord.Gait.RUN), 1.0, carry), 1.5, 1e-9, "a fixed speed overrides the gait")
	var off: MinerMotion.Constraints = MinerMotion.Constraints.new()
	off.movement_off = true
	var s: MinerMotion.State = MinerMotion.step(MinerMotion.State.new(), _rec(0.0, InputRecord.Gait.RUN, 12345), off, 1.0, open, 0.05, p).state
	assert_eq([s.x, s.y], [0.0, 0.0], "movement off freezes position")
	assert_eq(s.facing, 12345, "while facing still turns")
	var merged: MinerMotion.Constraints = MinerMotion.Constraints.most_restrictive([carry, tired, walk_only])
	assert_eq([merged.fixed_speed, merged.run_allowed, merged.walk_only], [1.5, false, true])


func test_gait_choice() -> void:
	assert_eq(MinerMotion.choose_gait(true, true, true), InputRecord.Gait.RUN, "run beats crouch")
	assert_eq(MinerMotion.choose_gait(true, true, false), InputRecord.Gait.CROUCH, "unless running is not allowed")
	assert_eq(MinerMotion.choose_gait(false, false, true), InputRecord.Gait.WALK)
