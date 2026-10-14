extends GutTest
## RTT settles within ±5 ms of an emulated 120 ms link within 10 s (NET-02), measured on top of
## the test loop's own round trip, so a coarse platform timer is not mistaken for the estimator.

const Emulator = preload("res://tests/support/udp_link_emulator.gd")
const Pump = preload("res://tests/support/net_pump.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_rtt_settles_on_a_120_ms_link() -> void:
	var run: RunState = RunState.create(1, ServerConfig.Mode.FRIENDS, false)
	var server_transport: EnetTransport = EnetTransport.new()
	assert_eq(server_transport.listen("127.0.0.1", 0), OK)
	var net: ServerNet = ServerNet.new(server_transport)
	run.add_system(net)
	var link: Emulator = Emulator.new()
	link.delay_usec = 0
	var port: int = link.start(server_transport.bound_port())
	var connection: ClientConnection = ClientConnection.new(EnetTransport.new())
	connection.start("127.0.0.1", port)
	var step: Callable = func() -> void:
		link.pump(Time.get_ticks_usec())
		net.pump(run)
		link.pump(Time.get_ticks_usec())
		connection.poll()
	# The loop's own round trip first: four hops through the emulator, each up to one pump late,
	# which is coarser on Windows. The clock must then find 120 ms on top of it.
	var warmed: bool = Pump.until(step, func() -> bool: return connection.clock.samples() >= 3, 10.0)
	assert_true(warmed, "the link carries pings")
	var baseline: float = connection.clock.rtt_ms()
	gut.p("loop round trip without delay: %.1f ms" % baseline)
	assert_lt(baseline, 20.0, "the test loop itself adds little")
	link.delay_usec = 60000  # each way
	var started: int = Time.get_ticks_usec()
	var settled: bool = Pump.until(step, func() -> bool:
		return absf(connection.clock.rtt_ms() - (120.0 + baseline)) <= 5.0, 10.0)
	var elapsed: float = (Time.get_ticks_usec() - started) / 1000000.0
	assert_true(settled, "RTT %.1f ms after %.1f s (%d samples; loop %.1f ms)" % [connection.clock.rtt_ms(), elapsed,
		connection.clock.samples(), baseline])
	assert_lt(elapsed, 10.5)
	var server_now: int = Time.get_ticks_usec()
	assert_lt(absi(connection.clock.server_time_estimate(server_now) - server_now), 5000, "offset estimate within 5 ms (one process, one clock)")
	connection.close()
	server_transport.close()
	link.close()
