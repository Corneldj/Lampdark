extends GutTest
## NET-02's handshake over the in-process transport: welcome, rejects, tokens, timeouts.

var hub: InProcessTransport.Hub
var run: RunState
var net: ServerNet


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	hub = InProcessTransport.Hub.new()
	run = RunState.create(1, ServerConfig.Mode.FRIENDS, false)
	var server_transport: InProcessTransport = InProcessTransport.new(hub)
	assert_eq(server_transport.listen("server", 1), OK)
	net = ServerNet.new(server_transport, 2)
	ServerSystems.install(run, net)


func _client(identity: String) -> ClientConnection:
	var connection: ClientConnection = ClientConnection.new(InProcessTransport.new(hub))
	connection.identity = identity
	assert_true(connection.start("server", 1))
	return connection


func _settle(clients: Array[ClientConnection], ticks: int = 6) -> void:
	for _i: int in ticks:
		for c: ClientConnection in clients:
			c.poll()
		run.run_tick()
	for c: ClientConnection in clients:
		c.poll()


func test_welcome() -> void:
	var client: ClientConnection = _client("alice")
	_settle([client])
	assert_eq(client.state, ClientConnection.State.CONNECTED)
	assert_eq(client.welcome.slot, 0)
	assert_eq(client.welcome.tick_hz, 20)
	assert_eq(client.welcome.session_token.length(), 32)
	assert_gt(client.frames_received, 0, "frames follow the welcome")
	assert_eq(client.welcome.client_tuning, "", "the shipped client table is current, so none is sent")


func test_build_mismatch_is_refused_before_any_game_data() -> void:
	var client: ClientConnection = _client("bob")
	client.build_id = "0.0.0+deadbee"
	_settle([client], 10)
	assert_eq(client.state, ClientConnection.State.REJECTED)
	assert_eq(client.reject_reason, Protocol.Reject.VERSION_MISMATCH)
	assert_eq(client.frames_received, 0, "no frame before Welcome")
	assert_eq(client.early_messages, 0, "nothing but the Reject")


func test_protocol_mismatch_is_refused() -> void:
	var client: ClientConnection = _client("carol")
	client.protocol_version = Protocol.PROTOCOL_VERSION + 1
	_settle([client])
	assert_eq(client.reject_reason, Protocol.Reject.VERSION_MISMATCH)


func test_full_server_refuses() -> void:
	var a: ClientConnection = _client("a")
	var b: ClientConnection = _client("b")
	var c: ClientConnection = _client("c")
	_settle([a, b, c])
	assert_eq(a.state, ClientConnection.State.CONNECTED)
	assert_eq(b.state, ClientConnection.State.CONNECTED)
	assert_ne(a.welcome.slot, b.welcome.slot)
	assert_eq(c.state, ClientConnection.State.REJECTED)
	assert_eq(c.reject_reason, Protocol.Reject.FULL)


func test_game_message_before_hello_is_a_bad_message() -> void:
	var raw: InProcessTransport = InProcessTransport.new(hub)
	var peer: int = raw.connect_to("server", 1)
	raw.poll()
	raw.send(peer, Lane.Id.INPUTS, Protocol.frame(Protocol.Msg.FRAME, PackedByteArray([1])))
	run.run_tick()
	var reply: Array[TransportEvent] = raw.poll()
	assert_eq(reply.size(), 1)
	var message: Dictionary = Protocol.unframe(reply[0].data)
	assert_eq(int(Variants.number(message["type"])), Protocol.Msg.REJECT)
	var payload: PackedByteArray = message["payload"]
	assert_eq(Protocol.read_u8(payload), Protocol.Reject.BAD_MESSAGE)


func test_session_token_survives_a_drop_for_rejoin() -> void:
	var client: ClientConnection = _client("dana")
	_settle([client])
	var token: String = client.session_token
	client.close()
	run.run_tick()
	assert_eq(net.dropped_slots, PackedInt64Array([0]), "the drop is reported in the tick it happens")
	_settle([], 2)
	assert_eq(net.dropped_slots, PackedInt64Array(), "and only in that tick")
	var session: Sessions.Session = net.sessions.find_by_token(token)
	assert_not_null(session, "NET-11 can recognise the rejoining player")
	assert_eq(session.identity, "dana")


func test_handshake_timeout_drops_a_silent_peer() -> void:
	net.handshake_timeout_usec = 50000
	var raw: InProcessTransport = InProcessTransport.new(hub)
	raw.connect_to("server", 1)
	run.run_tick()
	assert_eq(net.sessions.pending().size(), 1)
	OS.delay_usec(60000)
	run.run_tick()
	assert_eq(net.sessions.pending().size(), 0)
	var events: Array[TransportEvent] = raw.poll()
	assert_eq(events.size(), 2, "connected, then dropped")
	assert_eq(events[1].kind, TransportEvent.Kind.DROPPED)


func test_unknown_message_type_is_counted() -> void:
	var client: ClientConnection = _client("eve")
	_settle([client])
	client.transport.send(client.peer, Lane.Id.INPUTS, PackedByteArray([200, 0, 0, 0, 0]))
	client.transport.send(client.peer, Lane.Id.INPUTS, PackedByteArray([1, 2]))
	_settle([client], 2)
	assert_eq(int(Variants.number(net.bad_messages.values()[0])), 2)
