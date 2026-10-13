extends GutTest
## VIS-08 (GDD §14.1, §14.5): every flame state is a distinct moving shape, readable without colour.
## Each state's polygons are rasterised in greyscale (coverage only) and compared pixel by pixel: every
## state differs from the plain flame and from every other state, trembling and guttering move over
## time below the 3 Hz cap, and NET-10's migration hook draws the gutter shape with no sputter.

const W: int = 40
const H: int = 60
## Pixels two shapes must differ by to read as distinct at this size.
const DISTINCT: int = 12


func before_all() -> void:
	assert_true(Tuning.load_server())


## The coverage mask of a state's polygons at time t (flame base at the bottom centre).
func _raster(bits: int, t: float) -> PackedByteArray:
	var polys: Array[PackedVector2Array] = FlameStateView.shapes(bits, t)
	var out: PackedByteArray = PackedByteArray()
	out.resize(W * H)
	for y: int in H:
		for x: int in W:
			var p: Vector2 = Vector2(x + 0.5 - W / 2.0, y + 0.5 - (H - 4))
			var lit: bool = false
			for poly: PackedVector2Array in polys:
				lit = lit or Geometry2D.is_point_in_polygon(p, poly)
			out[y * W + x] = 255 if lit else 0
	return out


func _differ(a: PackedByteArray, b: PackedByteArray) -> int:
	var n: int = 0
	for i: int in a.size():
		if a[i] != b[i]:
			n += 1
	return n


func test_every_state_is_a_distinct_shape() -> void:
	var states: Array[int] = [0, FlameFlags.TREMBLE, FlameFlags.GUTTER, FlameFlags.CAP, FlameFlags.SHRINK, FlameFlags.FLARE_UP]
	var masks: Array[PackedByteArray] = []
	for bits: int in states:
		masks.append(_raster(bits, 0.1))
	for i: int in states.size():
		var area: int = _differ(masks[i], _empty())
		assert_gt(area, 20, "%s draws something" % _name(states[i]))
		for j: int in range(i + 1, states.size()):
			assert_gte(_differ(masks[i], masks[j]), DISTINCT, "%s vs %s in greyscale" % [_name(states[i]), _name(states[j])])


func _empty() -> PackedByteArray:
	var e: PackedByteArray = PackedByteArray()
	e.resize(W * H)
	return e


func _name(bits: int) -> String:
	return "base" if bits == 0 else ",".join(FlameFlags.names(bits))


func test_tremble_and_gutter_move_below_three_hz() -> void:
	var cap: float = Tuning.f(&"light.max_flash_hz")
	for bits: int in [FlameFlags.TREMBLE, FlameFlags.GUTTER]:
		var hz: float = FlameStateView.animation_hz(bits)
		assert_gt(hz, 0.0, "%s moves" % _name(bits))
		assert_lt(hz, cap, "%s stays below %.0f Hz" % [_name(bits), cap])
		var quarter: float = 0.25 / hz
		assert_gt(_differ(_raster(bits, 0.0), _raster(bits, quarter)), 4, "%s: a moving shape" % _name(bits))
		assert_eq(_differ(_raster(bits, 0.0), _raster(bits, 1.0 / hz)), 0, "%s: one period later, the same" % _name(bits))
	assert_eq(_differ(_raster(0, 0.0), _raster(0, 0.37)), 0, "the plain flame holds still")


func test_trembling_never_leans() -> void:
	for t: float in [0.0, 0.11, 0.23, 0.31]:
		var body: PackedVector2Array = FlameStateView.shapes(FlameFlags.TREMBLE, t)[0]
		var cx: float = 0.0
		for p: Vector2 in body:
			cx += p.x
		assert_almost_eq(cx / body.size(), 0.0, 0.35, "shivers in place at %.2f s" % t)


func test_migration_hook() -> void:
	var view: FlameStateView = FlameStateView.new()
	view.set_migration_gutter(true)
	assert_eq(view.shown_flags(), FlameFlags.GUTTER, "draws the gutter shape")
	assert_false(view.sputtering(), "no sputter")
	view.flags = FlameFlags.GUTTER
	assert_true(view.sputtering(), "a real gutter sputters")
	view.free()
