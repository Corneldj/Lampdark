extends GutTest
## MNR-14: the rigid segment (Gameplay §4.3; GDD §15.8). With agreeing inputs a stretcher moves at
## 2.5 tiles/s and the drum gear at 2.0, each carrier stepping every 10 ticks; a wounded carrier
## slows them to 2.0 and 1.6. The heading turns at most 15° a tick: a 90° change of input has turned
## it 90° in 6 ticks, not 5. An input more than 90° from the heading backs the load up, its heading
## kept. A move into rock is tried as rotation only, then translation only, then refused, never a
## knock; the capsule never overlaps rock and only touches it.

const EAST: int = 0
## InputScript.direction_byte(90): 64 of 255, 90.35° (an input byte cannot say 90° exactly).
const SOUTH: int = 64
const WEST: int = 128
## A wall of rock at x >= WALL_X.
const WALL_X: int = 12


func before_all() -> void:
	assert_true(Tuning.load_server())


func _open(_tile: Vector2i) -> bool:
	return false


func _wall(tile: Vector2i) -> bool:
	return tile.x >= WALL_X


## A 1-wide corridor along y = 10.
func _corridor(tile: Vector2i) -> bool:
	return tile.y != 10


## Both carriers push `dir` for `ticks` ticks from issue tick `from`; the results in order.
func _drive(seg: LoadSegment, dir: int, ticks: int, solid: Callable = Callable(), wounded: bool = false, from: int = 0) -> Array[LoadSegment.Result]:
	var out: Array[LoadSegment.Result] = []
	var is_solid: Callable = solid if solid.is_valid() else _open
	for i: int in ticks:
		out.append(seg.step(LoadSegment.Push.of(dir, from + i), LoadSegment.Push.of(dir, from + i), wounded, is_solid))
	return out


func _step_ticks(results: Array[LoadSegment.Result]) -> Array[int]:
	var out: Array[int] = []
	for i: int in results.size():
		for _n: int in results[i].steps:
			out.append(i)
	return out


func test_agreeing_carriers_move_it_at_its_speed_and_step_every_10_ticks() -> void:
	for case: Array in [[ItemKinds.Kind.STRETCHER, 2.5], [ItemKinds.Kind.DRUM_GEAR, 2.0]]:
		var kind: ItemKinds.Kind = int(Variants.number(case[0])) as ItemKinds.Kind
		var speed: float = float(Variants.number(case[1]))
		var seg: LoadSegment = LoadSegment.make(kind, Vector2(10.5, 10.5), 0)
		var results: Array[LoadSegment.Result] = _drive(seg, EAST, 40)
		assert_almost_eq(seg.x - 10.5, speed * 2.0, 1e-9, "%s: %.1f tiles/s for 2 s" % [ItemKinds.text_key(kind), speed])
		assert_almost_eq(seg.y, 10.5, 1e-9, "straight east")
		assert_eq(seg.heading, 0)
		assert_eq(_step_ticks(results), [9, 19, 29, 39] as Array[int], "each carrier steps every 10 ticks")
		var knocked: bool = false
		for r: LoadSegment.Result in results:
			knocked = knocked or r.knock
		assert_false(knocked)
	var gear: LoadSegment = LoadSegment.make(ItemKinds.Kind.DRUM_GEAR, Vector2.ZERO, 0)
	assert_eq([gear.length, LoadSegment.make(ItemKinds.Kind.STRETCHER, Vector2.ZERO, 0).length], [1.5, 2.0], "segments of 1.5 and 2 tiles")


func test_a_wounded_carrier_slows_the_load_20_percent() -> void:
	for case: Array in [[ItemKinds.Kind.STRETCHER, 2.0], [ItemKinds.Kind.DRUM_GEAR, 1.6]]:
		var kind: ItemKinds.Kind = int(Variants.number(case[0])) as ItemKinds.Kind
		var seg: LoadSegment = LoadSegment.make(kind, Vector2(10.5, 10.5), 0)
		_drive(seg, EAST, 20, Callable(), true)
		assert_almost_eq(seg.x - 10.5, float(Variants.number(case[1])), 1e-9, "%s: wounded" % ItemKinds.text_key(kind))


func test_a_90_degree_change_turns_the_load_in_6_ticks() -> void:
	var seg: LoadSegment = LoadSegment.make(ItemKinds.Kind.STRETCHER, Vector2(10.5, 10.5), 0)
	_drive(seg, EAST, 4)
	var turned: Array[int] = []
	for i: int in 8:
		_drive(seg, SOUTH, 1, Callable(), false, 4 + i)
		turned.append(seg.heading)
	var quarter: int = 16384
	assert_lt(turned[4], quarter, "5 ticks: not yet 90°")
	assert_gte(turned[5], quarter, "6 ticks: turned 90° (15° a tick)")
	assert_eq(turned[0], LoadSegment.degrees_u16(15.0), "15° in the first tick")
	assert_eq(turned[7], LoadSegment.dir_u16(SOUTH), "then on the input's heading, and no further")
	assert_gt(seg.y, 10.5 + 0.9, "moving south all the while")


func test_an_input_behind_backs_the_load_up() -> void:
	var seg: LoadSegment = LoadSegment.make(ItemKinds.Kind.STRETCHER, Vector2(20.5, 10.5), 0)
	_drive(seg, WEST, 20)
	assert_almost_eq(seg.x, 20.5 - 2.5, 0.01, "backed up west at its speed")
	assert_lt(absi(LoadSegment.signed_diff(0, seg.heading)), LoadSegment.degrees_u16(1.0), "still heading east (within the input's rounding)")
	# A quarter turn as a keyboard sends it (90.35°) still turns it forward.
	var fwd: LoadSegment = LoadSegment.make(ItemKinds.Kind.STRETCHER, Vector2(20.5, 10.5), 0)
	_drive(fwd, SOUTH, 10)
	assert_eq(fwd.heading, LoadSegment.dir_u16(SOUTH))


func test_a_blocked_move_is_tried_as_rotation_then_translation_then_refused() -> void:
	# Refused: heading east, its front carrier against the wall, pushed east.
	var seg: LoadSegment = LoadSegment.make(ItemKinds.Kind.STRETCHER, Vector2(WALL_X - 1.35, 10.5), 0)
	var x0: float = seg.x
	var r: LoadSegment.Result = _drive(seg, EAST, 1, _wall)[0]
	assert_true(r.blocked)
	assert_false(r.moved, "nothing fits: refused")
	assert_false(r.knock, "a refusal never knocks")
	assert_eq([seg.x, seg.y, seg.heading], [x0, 10.5, 0])
	# Rotation only: pushed a little south of east into the wall, it can still swing.
	var rot: LoadSegment = LoadSegment.make(ItemKinds.Kind.STRETCHER, Vector2(WALL_X - 1.35, 10.5), 0)
	r = _drive(rot, 7, 1, _wall)[0]
	assert_true(r.blocked and r.moved, "cut to rotation")
	assert_eq([rot.x, rot.y], [x0, 10.5], "the centre stays")
	assert_gt(rot.heading, 0, "but it turns")
	# Translation only: in a 1-wide corridor a south-east push cannot swing it, but slides it.
	var slide: LoadSegment = LoadSegment.make(ItemKinds.Kind.STRETCHER, Vector2(5.5, 10.5), 0)
	r = _drive(slide, 32, 1, _corridor)[0]
	assert_true(r.blocked and r.moved, "cut to translation")
	assert_eq(slide.heading, 0, "no swing in the corridor")
	assert_gt(slide.x, 5.5)
	assert_false(slide.collides(slide.x, slide.y, slide.heading, _corridor), "never into the rib")


func test_the_capsule_touches_rock_but_never_overlaps_it() -> void:
	var seg: LoadSegment = LoadSegment.make(ItemKinds.Kind.STRETCHER, Vector2(WALL_X - 1.35, 10.5), 0)
	assert_false(seg.collides(seg.x, seg.y, 0, _wall), "touching is not overlapping")
	assert_true(seg.collides(seg.x + 0.01, seg.y, 0, _wall))
	# A tile corner between the ends, inside the body: the segment's own width counts.
	var corner: Callable = func(tile: Vector2i) -> bool: return tile == Vector2i(10, 11)
	assert_true(seg.collides(10.5, 10.8, 0, corner), "0.2 from a rock tile's edge, mid-span")
	assert_false(seg.collides(10.5, 10.5, 0, corner), "0.5 from it: clear")
	assert_eq(LoadSegment.segment_box_distance_sq(0.0, 0.0, 4.0, 0.0, 1.0, -1.0, 2.0, 1.0), 0.0, "a segment through a box")
	assert_almost_eq(LoadSegment.segment_box_distance_sq(0.0, 0.0, 4.0, 0.0, 1.0, 0.5, 2.0, 1.5), 0.25, 1e-12)
