extends GutTest
## NET-05's client clock: the server-tick estimate, its smoothing, the depth nudge and the tick
## rate it gives.


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_estimate_and_smoothing() -> void:
	var c: ClientClock = ClientClock.new()
	c.on_frame(199, 1000000)
	assert_almost_eq(c.server_tick(1000000), 200.0, 1e-6, "the frame's end, on the received timeline")
	assert_almost_eq(c.shown_tick(1000000), 198.0, 1e-6, "rendered 100 ms behind it, with frames either side")
	c.on_frame(201, 1050000)  # arrived 50 ms late against the estimate
	assert_almost_eq(c.server_tick(1050000), 201.0 + 0.1, 0.05, "a late frame moves the estimate only a little")


func test_the_render_time_never_passes_the_newest_frame() -> void:
	for rtt_ms: int in [0, 120, 200, 300]:
		var c: ClientClock = ClientClock.new()
		var newest: int = 0
		for f: int in 100:
			newest = f
			c.on_frame(f, f * 50000 + rtt_ms * 500)
		var shown: float = c.shown_tick(99 * 50000 + rtt_ms * 500 + 49000)
		assert_lt(shown, float(newest), "%d ms RTT: rendering between frames, not extrapolating" % rtt_ms)


func test_the_nudge_keeps_the_buffer_at_its_target() -> void:
	var c: ClientClock = ClientClock.new()
	c.on_depth(0)
	assert_gt(c.nudge, 0.0, "an empty buffer: tick faster")
	c.on_depth(5)
	assert_almost_eq(c.nudge, -0.05, 1e-9, "never more than net.input_clock_nudge_max")
	c.on_depth(1)
	assert_eq(c.nudge, 0.0)


func test_ticks_due() -> void:
	var c: ClientClock = ClientClock.new()
	assert_eq(c.advance(0), 0)
	assert_eq(c.advance(1000000), 20, "20 Hz")
	c.on_depth(5)
	assert_eq(c.advance(2000000), 19, "nudged 5% slower")
