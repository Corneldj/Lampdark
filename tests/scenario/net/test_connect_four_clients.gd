extends GutTest
## Four bot clients connect and reach their first frame, over ENet and over the in-process
## transport, with the same game code (NET-02).

const Pump = preload("res://tests/support/net_pump.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _connect_four(server_transport: Transport, make_client: Callable, host: String, port: int) -> void:
	var run: RunState = RunState.create(9, ServerConfig.Mode.FRIENDS, false)
	var net: ServerNet = ServerNet.new(server_transport)
	ServerSystems.install(run, net)
	var clients: Array[ClientConnection] = []
	for i: int in 4:
		var transport: Transport = make_client.call()
		var connection: ClientConnection = ClientConnection.new(transport)
		connection.identity = "bot%d" % i
		connection.seat_request = Protocol.Seat.BOT
		assert_true(connection.start(host, port))
		clients.append(connection)
	var reached: bool = Pump.until(func() -> void:
		run.run_tick()
		for c: ClientConnection in clients:
			c.poll(),
		func() -> bool:
			for c: ClientConnection in clients:
				if c.frames_received == 0:
					return false
			return true,
		10.0)
	assert_true(reached, "all four reached a frame")
	var slots: Array[int] = []
	for c: ClientConnection in clients:
		assert_eq(c.state, ClientConnection.State.CONNECTED)
		slots.append(c.welcome.slot)
		c.close()
	slots.sort()
	assert_eq(slots, [0, 1, 2, 3] as Array[int])
	server_transport.close()


func test_four_bots_over_enet() -> void:
	var server: EnetTransport = EnetTransport.new()
	assert_eq(server.listen("127.0.0.1", 0), OK)
	_connect_four(server, func() -> Transport: return EnetTransport.new(), "127.0.0.1", server.bound_port())


func test_four_bots_in_process() -> void:
	var hub: InProcessTransport.Hub = InProcessTransport.Hub.new()
	var server: InProcessTransport = InProcessTransport.new(hub)
	assert_eq(server.listen("server", 1), OK)
	_connect_four(server, func() -> Transport: return InProcessTransport.new(hub), "server", 1)
