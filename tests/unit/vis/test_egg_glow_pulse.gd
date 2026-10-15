extends GutTest
## VIS-10: the hatch tell's pulse is a smooth swing at marks.egg_glow_pulse_hz, below 3 Hz; the client
## strips the hatch bit from the colour class and pulses only tiles that carry it.


func before_all() -> void:
	assert_true(Tuning.load_client())


func test_below_three_hertz_and_smooth() -> void:
	var hz: float = EggGlowView.pulse_hz()
	assert_lt(hz, 3.0)
	assert_almost_eq(hz, 1.0, 1e-6, "the starting 1 Hz")
	var period: float = 1.0 / hz
	assert_almost_eq(EggGlowView.level_at(0.0), 0.0, 1e-6)
	assert_almost_eq(EggGlowView.level_at(period * 0.5), EggGlowView.DEPTH, 1e-6, "full at the half period")
	assert_almost_eq(EggGlowView.level_at(period * 2.0), 0.0, 1e-6, "periodic")
	# Never more than one rise a period: sampled at 60 fps, the swing turns twice a period at most.
	var turns: int = 0
	var last: float = EggGlowView.level_at(0.0)
	var rising: bool = true
	for i: int in range(1, 61):
		var v: float = EggGlowView.level_at(i / 60.0)
		if (v > last) != rising:
			turns += 1
			rising = v > last
		last = v
	assert_lte(turns, 2, "no flashing: one swing in a second")


func test_hatch_bit_stripped_and_pulsing_only_there() -> void:
	var view: ReceivedView = ReceivedView.new()
	view.tiles[Vector2i(3, 3)] = PackedByteArray([50, 4 | TileBits.COLOUR_HATCH_BIT, 0])
	view.tiles[Vector2i(4, 3)] = PackedByteArray([50, 4, 0])
	var drawn: DrawnSet = DrawnSet.new()
	drawn.build(view, {"position": Vector2(3, 3), "facing": 0, "lamp": {}}, 0, -1)
	assert_eq(int(Variants.number(Variants.dict(drawn.tiles[Vector2i(3, 3)])["colour"])), 4, "the colour class, the bit stripped")
	var layer: EggGlowView = EggGlowView.new()
	layer.set_frame(drawn, Vector2.ZERO, 64.0, 0.0)
	assert_eq(layer.pulsing(), [Vector2i(3, 3)] as Array[Vector2i], "only the hatch-tell tile pulses")
	layer.free()
