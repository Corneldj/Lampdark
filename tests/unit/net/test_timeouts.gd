extends GutTest
## A connection silent for net.connection_timeout_s raises exactly one DROPPED on each side.

const Emulator = preload("res://tests/support/udp_link_emulator.gd")
const Pump = preload("res://tests/support/net_pump.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_silence_drops_each_side_exactly_once() -> void:
	var server: EnetTransport = EnetTransport.new()
	assert_eq(server.listen("127.0.0.1", 0), OK)
	var link: Emulator = Emulator.new()
	var port: int = link.start(server.bound_port())
	var client: EnetTransport = EnetTransport.new()
	var client_peer: int = client.connect_to("127.0.0.1", port)
	var server_drops: Array[TransportEvent] = []
	var client_drops: Array[TransportEvent] = []
	var server_connected: Array[bool] = [false]
	var step: Callable = func() -> void:
		link.pump(Time.get_ticks_usec())
		for event: TransportEvent in server.poll():
			if event.kind == TransportEvent.Kind.CONNECTED:
				server_connected[0] = true
			elif event.kind == TransportEvent.Kind.DROPPED:
				server_drops.append(event)
		for event: TransportEvent in client.poll():
			if event.kind == TransportEvent.Kind.DROPPED:
				client_drops.append(event)
	assert_true(Pump.until(step, func() -> bool: return server_connected[0] and client.is_connected_to(client_peer), 5.0))
	assert_eq(server.connection_timeout_usec, 5000000, "net.connection_timeout_s is 5 s")
	link.blackhole = true
	var silent_from: int = Time.get_ticks_usec()
	assert_true(Pump.until(step, func() -> bool: return server_drops.size() > 0 and client_drops.size() > 0, 8.0))
	var waited_s: float = (Time.get_ticks_usec() - silent_from) / 1000000.0
	assert_between(waited_s, 4.5, 6.5, "dropped after about 5 s of silence (%.2f s)" % waited_s)
	Pump.until(step, func() -> bool: return false, 1.5)
	assert_eq(server_drops.size(), 1, "exactly one drop on the server")
	assert_eq(client_drops.size(), 1, "exactly one drop on the client")
	assert_eq(server_drops[0].reason, "timeout")
	assert_eq(client_drops[0].reason, "timeout")
	client.close()
	server.close()
	link.close()
