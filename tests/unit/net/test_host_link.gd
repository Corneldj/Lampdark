extends GutTest
## STM-04's pieces in one process: the ready line, the control link (token first, members as the
## admission list, status, shutdown), MultiTransport serving two transports at once, and Path B end to
## end: a friend's SDR connection (the test Steam network) through the host's relay over real loopback
## ENet into a real ServerNet, which checks the friend's Hello against the relay's tag.

const Fake = preload("res://tests/unit/client/net/steam/fake_steam_api.gd")
const Net = preload("res://tests/unit/shared/net/fake_sns.gd")
const HOST_ID: int = 76561198000003003
const FRIEND_ID: int = 76561198000004004


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_the_ready_line() -> void:
	var line: String = HostLinkWire.ready_line(41234, "a1b2", 45678, 90294897415389192, 0)
	var f: Dictionary = HostLinkWire.parse_ready("12:00 [INFO] " + line)
	assert_eq(str(f["control"]).to_int(), 41234)
	assert_eq(str(f["token"]), "a1b2")
	assert_eq(str(f["game"]).to_int(), 45678)
	assert_eq(str(f["identity"]).to_int(), 90294897415389192, "a 64-bit game-server SteamID, exact")
	assert_eq(HostLinkWire.parse_ready("LB_READY control=1 token=x"), {}, "incomplete: not a ready line")


func _pump(link: HostLink, client: EnetTransport, frames: int = 30) -> Array[Dictionary]:
	var got: Array[Dictionary] = []
	for _i: int in frames:
		link.poll()
		for e: TransportEvent in client.poll():
			if e.kind == TransportEvent.Kind.MESSAGE:
				got.append(HostLinkWire.decode(e.data))
		client.flush()
		OS.delay_msec(2)
	return got


func test_the_control_link_wants_its_token() -> void:
	var link: HostLink = HostLink.new()
	assert_eq(link.start(0, 0, BuildInfo.new()), OK)
	assert_gt(link.control_port, 0)
	assert_eq(link.token.length(), 32)
	link.status_of = func() -> Dictionary: return {"clients": 0}
	var intruder: EnetTransport = EnetTransport.new()
	var ip: int = intruder.connect_to("127.0.0.1", link.control_port)
	_pump(link, intruder, 10)
	intruder.send(ip, Lane.Id.CONTROL, HostLinkWire.encode({"t": "shutdown"}))
	var asked: Array[int] = [0]
	link.shutdown_requested.connect(func() -> void: asked[0] += 1)
	_pump(link, intruder, 20)
	assert_eq(asked[0], 0, "no token: nothing obeyed")
	var host: EnetTransport = EnetTransport.new()
	var hp: int = host.connect_to("127.0.0.1", link.control_port)
	_pump(link, host, 10)
	host.send(hp, Lane.Id.CONTROL, HostLinkWire.encode({"t": "auth", "token": link.token}))
	var got: Array[Dictionary] = _pump(link, host)
	assert_true(got.any(func(m: Dictionary) -> bool: return str(m.get("t", "")) == "status"), "authed: a status")
	host.send(hp, Lane.Id.CONTROL, HostLinkWire.encode({"t": "members", "owner": str(HOST_ID), "ids": [str(HOST_ID), str(FRIEND_ID), "76561198000005005"],
		"code_users": [str(FRIEND_ID)], "vouched": []}))
	host.send(hp, Lane.Id.CONTROL, HostLinkWire.encode({"t": "shutdown"}))
	_pump(link, host)
	assert_true(link.admits(HOST_ID), "the owner")
	assert_true(link.admits(FRIEND_ID), "a code user")
	assert_false(link.admits(76561198000005005), "a member neither invited nor vouched")
	assert_false(link.admits(76561198000009009), "not a member")
	assert_eq(asked[0], 1, "the host's shutdown")
	link.close()
	host.close()
	intruder.close()


func test_multi_transport_serves_both() -> void:
	var hub_a: InProcessTransport.Hub = InProcessTransport.Hub.new()
	var hub_b: InProcessTransport.Hub = InProcessTransport.Hub.new()
	var a: InProcessTransport = InProcessTransport.new(hub_a)
	var b: InProcessTransport = InProcessTransport.new(hub_b)
	a.listen("s", 1)
	b.listen("s", 1)
	var both: Array[Transport] = [a, b]
	var multi: MultiTransport = MultiTransport.new(both)
	var run: RunState = RunState.create(1, ServerConfig.Mode.FRIENDS, false)
	var net: ServerNet = ServerNet.new(multi, 5)
	ServerSystems.install(run, net)
	var ca: ClientConnection = ClientConnection.new(InProcessTransport.new(hub_a))
	ca.identity = "ann"
	var cb: ClientConnection = ClientConnection.new(InProcessTransport.new(hub_b))
	cb.identity = "bo"
	ca.start("s", 1)
	cb.start("s", 1)
	for _i: int in 8:
		ca.poll()
		cb.poll()
		run.run_tick()
	assert_eq(ca.state, ClientConnection.State.CONNECTED)
	assert_eq(cb.state, ClientConnection.State.CONNECTED)
	assert_ne(ca.welcome.slot, cb.welcome.slot)
	assert_eq(multi.peers().size(), 2)
	assert_ne(multi.peers()[0] / MultiTransport.STRIDE, multi.peers()[1] / MultiTransport.STRIDE, "one peer from each transport")


func test_path_b_relays_a_friend_whose_hello_must_match_the_tag() -> void:
	var server_t: EnetTransport = EnetTransport.new()
	assert_eq(server_t.listen("127.0.0.1", 0), OK)
	var run: RunState = RunState.create(1, ServerConfig.Mode.FRIENDS, false)
	var net: ServerNet = ServerNet.new(server_t, 5)
	net.relay_token = "hosttoken"
	ServerSystems.install(run, net)
	var sns: RefCounted = Net.new()
	var host_api: SteamApi = Fake.new()
	var friend_api: SteamApi = Fake.new()
	sns.call(&"join", host_api, HOST_ID)
	sns.call(&"join", friend_api, FRIEND_ID)
	var relay: HostRelay = HostRelay.new(SdrTransport.new(host_api), server_t.bound_port(), "hosttoken")
	assert_eq(relay.listen(0), OK)
	for case: Array in [[str(FRIEND_ID), ClientConnection.State.CONNECTED, 0], ["76561198000000001", ClientConnection.State.REJECTED, Protocol.Reject.AUTH_FAILED]]:
		var friend: ClientConnection = ClientConnection.new(SdrTransport.new(friend_api))
		friend.identity = str(case[0])
		assert_true(friend.start(str(HOST_ID), 0))
		for _i: int in 60:
			host_api.run_callbacks()
			friend_api.run_callbacks()
			relay.poll()
			friend.poll()
			run.run_tick()
			OS.delay_msec(2)
		var want: ClientConnection.State = case[1]
		assert_eq(friend.state, want, "Hello as %s through the relay" % case[0])
		if want == ClientConnection.State.REJECTED:
			assert_eq(friend.reject_reason, Protocol.Reject.AUTH_FAILED, "not the SteamID Steam vouched for")
		else:
			assert_gt(friend.frames_received, 0, "frames come back through the relay")
		friend.close()
	assert_gt(relay.relayed, 0)
	relay.close()
	server_t.close()


func test_a_relay_tag_needs_the_hosts_token() -> void:
	var hub: InProcessTransport.Hub = InProcessTransport.Hub.new()
	var t: InProcessTransport = InProcessTransport.new(hub)
	t.listen("s", 1)
	var run: RunState = RunState.create(1, ServerConfig.Mode.FRIENDS, false)
	var net: ServerNet = ServerNet.new(t, 5)
	net.relay_token = "right"
	ServerSystems.install(run, net)
	var raw: InProcessTransport = InProcessTransport.new(hub)
	var peer: int = raw.connect_to("s", 1)
	raw.poll()
	run.run_tick()
	raw.send(peer, Lane.Id.CONTROL, Protocol.relay_tag("wrong", FRIEND_ID))
	run.run_tick()
	var rejected: bool = false
	for e: TransportEvent in raw.poll():
		if e.kind == TransportEvent.Kind.MESSAGE:
			var m: Dictionary = Protocol.unframe(e.data)
			rejected = rejected or Variants.whole(m.get("type", 0)) == Protocol.Msg.REJECT
	assert_true(rejected, "a tag without the host's token is refused")
