extends GutTest
## MNR-14: the knock (Gameplay §4.3; GDD §15.8). Inputs 46° apart for 5 ticks give one knock on the
## fifth and a halt, held until the inputs agree again; 44° apart the load moves along their
## average. One carrier still while the other moves for over 200 ms knocks; a 150 ms disagreement
## does not, and the load keeps its last agreed velocity through it. By issue tick: a carrier whose
## inputs arrive five ticks later never makes a knock by lag alone, only by a real disagreement; a
## starved input stops the load without one.

const EAST: int = 0
## 33 and 31 input steps from east: 46.6° and 43.8° (an input byte is 360/255°).
const APART_46: int = 33
const APART_44: int = 31
const STILL: int = InputRecord.NO_DIRECTION


func before_all() -> void:
	assert_true(Tuning.load_server())


func _open(_tile: Vector2i) -> bool:
	return false


func _step(seg: LoadSegment, front: int, rear: int, front_stamp: int, rear_stamp: int = -1) -> LoadSegment.Result:
	return seg.step(LoadSegment.Push.of(front, front_stamp), LoadSegment.Push.of(rear, front_stamp if rear_stamp < 0 else rear_stamp), false, _open)


func _moving(at_tick: int) -> LoadSegment:
	var seg: LoadSegment = LoadSegment.make(ItemKinds.Kind.STRETCHER, Vector2(10.5, 10.5), 0)
	for t: int in at_tick:
		_step(seg, EAST, EAST, t)
	return seg


func test_46_degrees_apart_for_5_ticks_knocks_once_and_halts() -> void:
	var seg: LoadSegment = _moving(10)
	var knocks: Array[int] = []
	var xs: Array[float] = []
	for i: int in 10:
		if _step(seg, EAST, APART_46, 10 + i).knock:
			knocks.append(i + 1)
		xs.append(seg.x)
	assert_eq(knocks, [5] as Array[int], "one knock, on the fifth tick of disagreement (over 200 ms)")
	assert_gt(xs[3], xs[2], "ticks 1-4: it keeps its last agreed velocity")
	assert_eq(xs[4], xs[3], "the knock halts it that tick")
	assert_eq(xs[9], xs[4], "and it stays halted while they disagree")
	assert_true(seg.halted)
	_step(seg, EAST, EAST, 20)
	assert_false(seg.halted, "agreeing again frees it")
	assert_gt(seg.x, xs[9])


func test_44_degrees_apart_it_moves_along_the_average() -> void:
	var seg: LoadSegment = LoadSegment.make(ItemKinds.Kind.STRETCHER, Vector2(10.5, 10.5), 0)
	for t: int in 20:
		assert_false(_step(seg, EAST, APART_44, t).knock)
	assert_gt(seg.x, 10.5 + 2.0, "it moved")
	var average: int = LoadSegment.dir_u16(APART_44) / 2
	assert_almost_eq(seg.heading, average, 1, "heading the average of the two, 21.9°")
	assert_almost_eq((seg.y - 10.5) / (seg.x - 10.5), tan(TAU * average / 65536.0), 1e-6, "along the average")


func test_one_still_and_one_moving_knocks_after_200_ms() -> void:
	var seg: LoadSegment = LoadSegment.make(ItemKinds.Kind.STRETCHER, Vector2(10.5, 10.5), 0)
	var knocks: Array[int] = []
	for i: int in 8:
		if _step(seg, EAST, STILL, i).knock:
			knocks.append(i + 1)
	assert_eq(knocks, [5] as Array[int], "the fifth tick: over 200 ms")
	assert_eq(seg.x, 10.5, "a load at rest never moved for one carrier alone")
	# Moving, then the rear carrier stops for 5 ticks: a knock.
	var moving: LoadSegment = _moving(10)
	knocks.clear()
	for i: int in 6:
		if _step(moving, EAST, STILL, 10 + i).knock:
			knocks.append(i + 1)
	assert_eq(knocks, [5] as Array[int])


func test_a_150_ms_disagreement_does_not_knock() -> void:
	var seg: LoadSegment = _moving(10)
	var before: float = seg.x
	for i: int in 3:
		assert_false(_step(seg, EAST, STILL, 10 + i).knock, "3 ticks: 150 ms")
	for i: int in 10:
		assert_false(_step(seg, EAST, EAST, 13 + i).knock)
	assert_almost_eq(seg.x - before, 13 * 0.125, 1e-9, "it kept its velocity through the disagreement")
	# 46° for 4 ticks: 200 ms is not over 200 ms.
	for i: int in 4:
		assert_false(_step(seg, EAST, APART_46, 23 + i).knock)
	assert_false(_step(seg, EAST, EAST, 27).knock)


func test_lag_alone_never_knocks_but_a_real_disagreement_does() -> void:
	# The rear carrier's inputs arrive 5 ticks after the front's: their stamps lag 5.
	var seg: LoadSegment = LoadSegment.make(ItemKinds.Kind.STRETCHER, Vector2(10.5, 10.5), 0)
	var lag: int = 5
	for t: int in 10:
		_step(seg, EAST, EAST, t, t - lag)
	# Both turn on the same shown tick (10): the front's turn is consumed at 10, the rear's at 15.
	var knocked: bool = false
	for t: int in range(10, 30):
		var rear: int = APART_46 if t >= 10 + lag else EAST
		knocked = knocked or _step(seg, APART_46, rear, t, t - lag).knock
	assert_false(knocked, "five ticks of disagreement by arrival, none by issue tick")
	# The rear never turns: by issue tick that is over 200 ms, five ticks later than without lag.
	var real: LoadSegment = LoadSegment.make(ItemKinds.Kind.STRETCHER, Vector2(10.5, 10.5), 0)
	for t: int in 10:
		_step(real, EAST, EAST, t, t - lag)
	var at: int = -1
	for t: int in range(10, 30):
		if _step(real, APART_46, EAST, t, t - lag).knock:
			at = t
	assert_eq(at, 10 + 4 + lag, "knocked once the rear's issued inputs show 5 ticks of it")


func test_a_starved_input_stops_the_load_without_a_knock() -> void:
	var seg: LoadSegment = _moving(10)
	var at: float = seg.x
	for i: int in 20:
		var r: LoadSegment.Result = seg.step(LoadSegment.Push.of(EAST, 10 + i), LoadSegment.Push.of(STILL, 9, true), false, _open)
		assert_false(r.knock)
	assert_eq(seg.x, at, "it waits for both carriers' intent")
