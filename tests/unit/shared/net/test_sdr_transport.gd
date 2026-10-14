extends GutTest
## STM-03's SdrTransport against a fake Steam Networking Sockets: three connections per peer by
## lane group, lane bytes and unreliable sequencing, the authenticated SteamID checked against
## Hello (auth_failed), status mapped to NET-02's events (one dropped per side), admission, insecure
## connections refused, a flush per tick, Steam's ping as the round trip, relay-only and the timeouts
## set before any connection, and fake conditions refused in release builds.

const Fake = preload("res://tests/unit/client/net/steam/fake_steam_api.gd")
const Net = preload("res://tests/unit/shared/net/fake_sns.gd")
const SERVER_ID: int = 76561198000001001
const CLIENT_ID: int = 76561198000002002

var net: RefCounted
var server_api: SteamApi
var client_api: SteamApi


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	net = Net.new()
	server_api = Fake.new()
	client_api = Fake.new()
	net.call(&"join", server_api, SERVER_ID)
	net.call(&"join", client_api, CLIENT_ID)


func _pump(transports: Array[SdrTransport], rounds: int = 4) -> Array[Array]:
	var out: Array[Array] = [[], []]
	for _r: int in rounds:
		server_api.run_callbacks()
		client_api.run_callbacks()
		for i: int in transports.size():
			Variants.array(out[i]).append_array(transports[i].poll())
	return out


func _pair() -> Array:
	var s: SdrTransport = SdrTransport.new(server_api)
	var c: SdrTransport = SdrTransport.new(client_api)
	assert_eq(s.listen("", 0), OK)
	var peer: int = c.connect_to(str(SERVER_ID), 0)
	assert_gt(peer, 0)
	var ev: Array[Array] = _pump([s, c])
	var server_peer: int = -1
	for e: Variant in Variants.array(ev[0]):
		var t: TransportEvent = e
		if t.kind == TransportEvent.Kind.CONNECTED:
			server_peer = t.peer
	return [s, c, server_peer, peer]


func test_three_connections_and_every_lane_both_ways() -> void:
	var p: Array = _pair()
	var s: SdrTransport = p[0]
	var c: SdrTransport = p[1]
	assert_gt(Variants.whole(p[2]), 0, "the server saw the client connect")
	assert_true(c.is_connected_to(Variants.whole(p[3])))
	var vports: Dictionary = {}
	for raw: Variant in Variants.dict(net.get(&"conns")).values():
		vports[Variants.whole(Variants.dict(raw)["vport"])] = true
	assert_eq(vports.keys().size(), 3, "control, bulk and real-time on their own virtual ports")
	for lane: int in Lane.COUNT:
		assert_eq(c.send(Variants.whole(p[3]), lane, PackedByteArray([lane, 9])), OK)
		assert_eq(s.send(Variants.whole(p[2]), lane, PackedByteArray([lane, 7])), OK)
	c.flush()
	s.flush()
	var ev: Array[Array] = _pump([s, c], 2)
	for side: int in 2:
		var lanes: Array[int] = []
		for e: Variant in Variants.array(ev[side]):
			var t: TransportEvent = e
			if t.kind == TransportEvent.Kind.MESSAGE:
				lanes.append(t.lane)
				assert_eq(t.data[0], t.lane, "the payload arrives whole, on its lane")
		lanes.sort()
		assert_eq(lanes, [0, 1, 2, 3, 4, 5] as Array[int], "side %d: all six lanes" % side)
	assert_gte(Variants.whole(net.get(&"flushes")), 6, "one flush per connection per tick")


func test_lane_groups() -> void:
	assert_eq(SdrTransport.GROUP_OF[Lane.Id.CONTROL], 0)
	assert_eq(SdrTransport.GROUP_OF[Lane.Id.DEBUG], 0)
	assert_eq(SdrTransport.GROUP_OF[Lane.Id.BULK], 1, "bulk alone: a big transfer delays nothing else")
	for lane: int in [Lane.Id.FRAMES, Lane.Id.INPUTS, Lane.Id.VOICE]:
		assert_eq(SdrTransport.GROUP_OF[lane], 2, "%s unreliable, apart from every reliable lane" % Lane.lane_name(lane))


func test_unreliable_is_sequenced_and_reliable_is_ordered_under_loss_and_reordering() -> void:
	var p: Array = _pair()
	var s: SdrTransport = p[0]
	var c: SdrTransport = p[1]
	net.set(&"loss", 0.05)
	net.set(&"reorder", 0.05)
	net.set(&"duplicate_share", 0.02)
	for i: int in 10000:
		var n: PackedByteArray = PackedByteArray()
		n.resize(4)
		n.encode_u32(0, i)
		c.send(Variants.whole(p[3]), Lane.Id.CONTROL, n)
		c.send(Variants.whole(p[3]), Lane.Id.VOICE, n)
		if i % 50 == 49:
			c.flush()
	c.flush()
	var reliable: Array[int] = []
	var voice: Array[int] = []
	for _r: int in 40:
		for e: Variant in Variants.array(_pump([s, c], 1)[0]):
			var t: TransportEvent = e
			if t.kind != TransportEvent.Kind.MESSAGE:
				continue
			if t.lane == Lane.Id.CONTROL:
				reliable.append(t.data.decode_u32(0))
			elif t.lane == Lane.Id.VOICE:
				voice.append(t.data.decode_u32(0))
	assert_eq(reliable.size(), 10000, "every reliable message")
	var in_order: bool = true
	for i: int in reliable.size():
		if reliable[i] != i:
			in_order = false
	assert_true(in_order, "reliable: all 10,000 in order")
	var monotonic: bool = true
	for i: int in range(1, voice.size()):
		if voice[i] <= voice[i - 1]:
			monotonic = false
	assert_true(monotonic, "unreliable: never an older message after a newer one, nor a duplicate")
	assert_between(voice.size(), 8800, 9600, "about 5% lost and some reordered dropped")


func test_the_sequence_wraps() -> void:
	var p: Array = _pair()
	var s: SdrTransport = p[0]
	var c: SdrTransport = p[1]
	var got: int = 0
	for i: int in 70000:
		c.send(Variants.whole(p[3]), Lane.Id.INPUTS, PackedByteArray([1]))
		if i % 1000 == 999:
			for e: TransportEvent in Variants.array(_pump([s, c], 1)[0]):
				if e.kind == TransportEvent.Kind.MESSAGE:
					got += 1
	for e: TransportEvent in Variants.array(_pump([s, c], 1)[0]):
		if e.kind == TransportEvent.Kind.MESSAGE:
			got += 1
	assert_eq(got, 70000, "past 65,535 the sequence wraps and delivery carries on")


func test_hello_must_be_the_authenticated_steamid() -> void:
	var run: RunState = RunState.create(1, ServerConfig.Mode.FRIENDS, false)
	var s: SdrTransport = SdrTransport.new(server_api)
	assert_eq(s.listen("", 0), OK)
	var server_net: ServerNet = ServerNet.new(s, 5)
	ServerSystems.install(run, server_net)
	for case: Array in [[str(CLIENT_ID), ClientConnection.State.CONNECTED], ["76561198099999999", ClientConnection.State.REJECTED]]:
		var c: ClientConnection = ClientConnection.new(SdrTransport.new(client_api))
		c.identity = str(case[0])
		assert_true(c.start(str(SERVER_ID), 0))
		for _i: int in 12:
			server_api.run_callbacks()
			client_api.run_callbacks()
			c.poll()
			run.run_tick()
		var want: ClientConnection.State = case[1]
		assert_eq(c.state, want, "Hello as %s" % case[0])
		if c.state == ClientConnection.State.REJECTED:
			assert_eq(c.reject_reason, Protocol.Reject.AUTH_FAILED, "another SteamID: auth_failed")
		c.close()
	var src: String = FileAccess.get_file_as_string("res://server/net/server_net.gd")
	assert_true(src.contains("transport.verified_identity(session.peer)"))


func test_one_dropped_per_side_and_a_severed_link_is_a_timeout() -> void:
	var p: Array = _pair()
	var s: SdrTransport = p[0]
	var c: SdrTransport = p[1]
	c.disconnect_peer(Variants.whole(p[3]))
	var ev: Array[Array] = _pump([s, c], 3)
	var drops: int = 0
	for e: TransportEvent in Variants.array(ev[0]):
		if e.kind == TransportEvent.Kind.DROPPED:
			drops += 1
			assert_eq(e.reason, "disconnected")
	assert_eq(drops, 1, "the server: exactly one dropped, for three connections closing")
	var q: Array = _pair()
	var handle: int = Variants.whole(Variants.dict(net.get(&"conns")).keys().max())
	net.call(&"sever", handle)
	var ev2: Array[Array] = _pump([q[0], q[1]], 3)
	var reasons: Array[String] = []
	for side: int in 2:
		for e: TransportEvent in Variants.array(ev2[side]):
			if e.kind == TransportEvent.Kind.DROPPED:
				reasons.append(e.reason)
	assert_eq(reasons, ["timeout", "timeout"] as Array[String], "one each side")


func test_admission_and_insecure_connections() -> void:
	var s: SdrTransport = SdrTransport.new(server_api)
	s.admission = func(steam_id: int) -> bool: return steam_id != CLIENT_ID
	assert_eq(s.listen("", 0), OK)
	var c: SdrTransport = SdrTransport.new(client_api)
	var peer: int = c.connect_to(str(SERVER_ID), 0)
	_pump([s, c])
	assert_false(c.is_connected_to(peer), "not admitted: never connected")
	assert_eq(s.peers().size(), 0)
	net.set(&"insecure", true)
	var s2: SdrTransport = SdrTransport.new(server_api)
	assert_eq(s2.listen("", 10), OK)
	var c2: SdrTransport = SdrTransport.new(client_api)
	var peer2: int = c2.connect_to(str(SERVER_ID), 10)
	_pump([s2, c2])
	assert_false(c2.is_connected_to(peer2), "an unauthenticated or unencrypted connection is refused")
	assert_gt(c2.insecure_refused + s2.insecure_refused, 0)


func test_identity_stats_and_settings() -> void:
	var p: Array = _pair()
	var s: SdrTransport = p[0]
	assert_eq(s.verified_identity(Variants.whole(p[2])), str(CLIENT_ID), "Steam's word on who connected")
	assert_eq(EnetTransport.new().verified_identity(1), "", "ENet authenticates nobody")
	assert_almost_eq(s.stats(Variants.whole(p[2])).rtt_ms, 37.0, 0.01, "Steam's ping is the round trip")
	var cfg: Dictionary = net.get(&"global_config")
	assert_eq(Variants.whole(cfg[SteamApi.SNS_CONFIG_ICE_ENABLE]), SteamApi.SNS_ICE_DISABLE, "relay only")
	assert_eq(Variants.whole(cfg[SteamApi.SNS_CONFIG_TIMEOUT_CONNECTED]), roundi(Tuning.f(&"net.connection_timeout_s") * 1000.0))
	assert_eq(Variants.whole(cfg[SteamApi.SNS_CONFIG_TIMEOUT_INITIAL]), roundi(Tuning.f(&"net.handshake_timeout_s") * 1000.0))
	assert_eq(c_peer_host_refused(), -1, "a host that is no SteamID is refused")


func c_peer_host_refused() -> int:
	return SdrTransport.new(client_api).connect_to("10.0.0.1", 0)


func test_fake_conditions_refused_in_release() -> void:
	var dev: BuildInfo = BuildInfo.new()
	dev.flavour = BuildInfo.Flavour.QA
	assert_true(SdrTransport.set_fake_conditions(client_api, dev, 250, 2.0))
	var cfg: Dictionary = net.get(&"global_config")
	assert_eq(Variants.whole(cfg[SteamApi.SNS_CONFIG_FAKE_LAG_SEND]) + Variants.whole(cfg[SteamApi.SNS_CONFIG_FAKE_LAG_RECV]), 250)
	assert_almost_eq(float(Variants.number(cfg[SteamApi.SNS_CONFIG_FAKE_LOSS_SEND])) * 2.0, 2.0, 1e-6)
	var release: BuildInfo = BuildInfo.new()
	release.flavour = BuildInfo.Flavour.RELEASE
	net.set(&"global_config", {})
	assert_false(SdrTransport.set_fake_conditions(client_api, release, 250, 2.0), "release: refused")
	assert_true(Variants.dict(net.get(&"global_config")).is_empty(), "nothing set")
	var parsed: Dictionary = DebugCommands.parse("sdr_fake 250 2")
	assert_true(Variants.flag(parsed["ok"]))
	assert_eq(DebugCommands.where("sdr_fake"), DebugCommands.Where.CLIENT)
	var a: LaunchArgs = LaunchArgs.parse(PackedStringArray(), PackedStringArray(["--sdr-fake", "250,2"]), dev)
	assert_eq(a.client.sdr_fake, "250,2")
	var r: LaunchArgs = LaunchArgs.parse(PackedStringArray(), PackedStringArray(["--sdr-fake", "250,2"]), release)
	assert_eq(r.client.sdr_fake, "", "release builds ignore the flag")


func test_nothing_above_the_transport_reads_an_address_from_steam() -> void:
	var hits: Array[String] = []
	for dir: String in ["res://client", "res://server", "res://shared"]:
		_scan(dir, hits)
	assert_eq(hits, [] as Array[String], "remote_address or a pop's address is read nowhere")


func _scan(dir: String, hits: Array[String]) -> void:
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			var src: String = FileAccess.get_file_as_string(dir.path_join(f))
			# Steam's connection info carries "remote_address": nothing may read it (ENet's own
			# get_remote_address, for local dev peers, is another matter).
			if src.contains("\"remote_address\"") or src.contains("getListenSocketAddress") or src.contains("\"remote_pop\""):
				hits.append(dir.path_join(f))
	for sub: String in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(sub), hits)
