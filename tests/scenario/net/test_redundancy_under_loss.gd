extends GutTest
## NET-03 under loss: with 2% loss at 120 ms RTT the server consumes the real input in at least
## 99.9% of ticks; one-shot actions apply exactly once under 10% loss with duplication; and the
## uplink without voice stays under net.up_budget_kbps over real ENet, overhead included.

const Rig = preload("res://tests/support/input_rig.gd")
const Emulator = preload("res://tests/support/udp_link_emulator.gd")
const Pump = preload("res://tests/support/net_pump.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


## A busy player: aiming with the mouse every tick, changing direction every quarter second,
## gait every second, and holding a control on and off.
func _moving_input(counter: Array[int]) -> InputRecord:
	var n: int = counter[0]
	var r: InputRecord = InputRecord.new()
	r.facing = (n * 997) & 0xFFFF
	r.move_dir = (n / 5 * 31) % 255
	r.gait = (n / 20 % 3) as InputRecord.Gait
	r.holds = InputRecord.HOLD_CHECK_LAMP if n % 40 < 10 else 0
	counter[0] += 1
	return r


func test_real_inputs_under_two_percent_loss_at_120_ms() -> void:
	var rig: Rig = Rig.new(0x0E73)
	var counter: Array[int] = [0]
	rig.make_input = func() -> InputRecord: return _moving_input(counter)
	# The link is set before connecting: a sudden rise in latency mid-run eats the buffer's
	# depth until NET-05's clock nudge restores it, which is not what this measures.
	rig.set_link(60, 20000)
	assert_true(rig.connect_and_settle())
	rig.ticks(20)
	var tally: Array[int] = [0, 0]  # real, not real
	rig.on_tick = func(r: Rig) -> void:
		var c: InputBuffer.Consumed = r.consumed()
		if c != null:
			tally[0 if c.real else 1] += 1
	rig.ticks(10000)
	var total: int = tally[0] + tally[1]
	var ratio: float = float(tally[0]) / total
	gut.p("real inputs %d of %d (%.3f%%); packets dropped %d up, %d down" % [tally[0], total, ratio * 100.0,
		rig.client_link.dropped, rig.server_link.dropped])
	assert_gt(rig.client_link.dropped, 150, "the link really lost about 2% of inputs")
	assert_gte(ratio, 0.999)
	assert_eq(rig.buffer().clamped_stamps, 0, "honest stamps are never clamped")
	assert_eq(rig.connection.state, ClientConnection.State.CONNECTED)


func test_actions_apply_exactly_once_under_loss_and_duplication() -> void:
	var rig: Rig = Rig.new(0xAC71)
	var counter: Array[int] = [0]
	rig.make_input = func() -> InputRecord: return _moving_input(counter)
	assert_true(rig.connect_and_settle())
	rig.set_link(60, 100000, 100000)
	var applied: Array[int] = []
	rig.on_tick = func(r: Rig) -> void:
		var c: InputBuffer.Consumed = r.consumed()
		if c != null:
			for a: ActionRecord in c.actions:
				applied.append(a.arg)
	var queued: int = 0
	for t: int in 2000:
		if t % 7 == 0 and queued < 200:
			rig.connection.inputs.queue_action((queued % 5) as ActionRecord.Kind, queued, t, 0)
			queued += 1
		rig.ticks(1)
	rig.ticks(100)
	var expected: Array[int] = []
	for i: int in queued:
		expected.append(i)
	gut.p("actions %d applied of %d; inputs dropped %d, duplicated %d" % [applied.size(), queued,
		rig.client_link.dropped, rig.client_link.duplicated])
	assert_gt(rig.client_link.duplicated, 150, "the link really duplicated about 10% of inputs")
	assert_eq(applied, expected, "each action once, in order")
	assert_eq(rig.connection.inputs.pending_actions().size(), 0, "every action acknowledged")


## Over real ENet through a UDP link with 2% loss and 120 ms RTT: every datagram the client
## sends, ENet headers included, plus 28 bytes of IPv4 and UDP headers each.
func test_uplink_stays_under_budget() -> void:
	var server: EnetTransport = EnetTransport.new()
	assert_eq(server.listen("127.0.0.1", 0), OK)
	var link: Emulator = Emulator.new()
	var link_port: int = link.start(server.bound_port())
	var run: RunState = RunState.create(5, ServerConfig.Mode.FRIENDS, false)
	var net: ServerNet = ServerNet.new(server)
	ServerSystems.install(run, net)
	var connection: ClientConnection = ClientConnection.new(EnetTransport.new())
	assert_true(connection.start("127.0.0.1", link_port))
	var clock: Dictionary = {"next_tick": Time.get_ticks_usec(), "client_ticks": 0}
	var counter: Array[int] = [0]
	var tick_usec: int = 50000
	var step: Callable = func() -> void:
		var now: int = Time.get_ticks_usec()
		link.pump(now)
		connection.poll()
		var next_tick: int = clock["next_tick"]
		if now >= next_tick:
			clock["next_tick"] = next_tick + tick_usec
			run.run_tick()
			if connection.state == ClientConnection.State.CONNECTED:
				var n: int = clock["client_ticks"]
				clock["client_ticks"] = n + 1
				# A callout, signal or chalk mark every second: far busier than real play.
				if n % 20 == 0:
					connection.inputs.queue_action(ActionRecord.Kind.CALLOUT, n)
				connection.inputs.send_tick(connection, _moving_input(counter), connection.last_frame_tick)
		link.pump(Time.get_ticks_usec())
	assert_true(Pump.until(step, func() -> bool: return connection.frames_received > 5, 5.0), "connected")
	link.loss_ppm = 20000
	link.delay_usec = 60000
	var start_bytes: int = link.client_bytes
	var start_datagrams: int = link.client_datagrams
	var start_usec: int = Time.get_ticks_usec()
	Pump.until(step, func() -> bool: return false, 6.0)
	var seconds: float = (Time.get_ticks_usec() - start_usec) / 1000000.0
	var datagrams: int = link.client_datagrams - start_datagrams
	var wire_bytes: int = link.client_bytes - start_bytes + 28 * datagrams
	var kbps: float = wire_bytes * 8.0 / seconds / 1000.0
	var budget: float = Tuning.f(&"net.up_budget_kbps")
	gut.p("uplink %.2f kbps over %.1f s: %d datagrams, %.1f bytes each on the wire (budget %.0f kbps)" % [
		kbps, seconds, datagrams, float(wire_bytes) / maxi(datagrams, 1), budget])
	assert_gt(datagrams, 100, "inputs flowed for the whole window")
	assert_lt(kbps, budget)
	connection.close()
	server.close()
	link.close()
