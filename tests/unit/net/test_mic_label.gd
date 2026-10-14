extends GutTest
## SND-10: the crew-list label flag. The client sends `mute_label` on joining and on change; the
## server keeps it per slot for UI-04's crew list, shows the label until told otherwise, and
## counts anything malformed. The message is one byte and carries nothing about speaking.

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


func _settle(clients: Array[ClientConnection], ticks: int = 6) -> void:
	for _i: int in ticks:
		for c: ClientConnection in clients:
			c.poll()
		run.run_tick()
	for c: ClientConnection in clients:
		c.poll()


func _joined(identity: String) -> ClientConnection:
	var c: ClientConnection = ClientConnection.new(InProcessTransport.new(hub))
	c.identity = identity
	assert_true(c.start("server", 1))
	_settle([c])
	assert_eq(c.state, ClientConnection.State.CONNECTED)
	return c


func test_the_label_is_shown_until_the_client_says_otherwise() -> void:
	var c: ClientConnection = _joined("alice")
	assert_true(net.mute_label(c.welcome.slot), "unknown: shown")
	assert_eq(c.send_mic_label(false), OK)
	_settle([c], 2)
	assert_false(net.mute_label(c.welcome.slot), "voice enabled: no label")
	c.send_mic_label(true)
	_settle([c], 2)
	assert_true(net.mute_label(c.welcome.slot), "muted again")


func test_one_byte_and_nothing_else() -> void:
	assert_eq(Protocol.mic_label(true).size(), 5 + 1, "a type, a length and one byte")
	var c: ClientConnection = _joined("bob")
	var before: int = int(Variants.number(net.bad_messages.get(c.peer, 0)))
	c.send(Lane.Id.CONTROL, PackedByteArray([1, 2]), Protocol.Msg.MIC_LABEL)
	c.send(Lane.Id.CONTROL, PackedByteArray([7]), Protocol.Msg.MIC_LABEL)
	_settle([c], 2)
	assert_eq(int(Variants.number(net.bad_messages.values()[0])) - before, 2, "malformed labels are counted, not applied")
	assert_true(net.mute_label(c.welcome.slot))


func test_each_slot_has_its_own_label() -> void:
	var a: ClientConnection = _joined("ann")
	var b: ClientConnection = _joined("ben")
	a.send_mic_label(false)
	_settle([a, b], 2)
	assert_false(net.mute_label(a.welcome.slot))
	assert_true(net.mute_label(b.welcome.slot))
