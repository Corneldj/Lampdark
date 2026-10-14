extends GutTest
## STM-03 live (manual: LB_STEAM_LIVE=1 with Steam running, from game/; pending otherwise and in CI).
## One account cannot reach itself through a relay, so Steam joins the two ends with its in-process
## pipe: the real Steam Networking Sockets calls run end to end, with Steam's authentication and
## encryption, but not the relayed path (QA-03's rig of accounts on separate networks takes that).
## A server and a client in this process complete NET-02's handshake over SdrTransport; a Hello as
## another SteamID is refused with auth_failed; every lane carries; closing drops each side once.


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_handshake_lanes_and_close_over_steam() -> void:
	if OS.get_environment("LB_STEAM_LIVE") != "1":
		pending("manual: LB_STEAM_LIVE=1 with Steam running")
		return
	var api: SteamApi = SteamApi.new()
	var steam: SteamService = SteamService.new(api)
	add_child_autofree(steam)
	assert_eq(steam.boot(false, false, ""), SteamService.Boot.CONTINUE)
	assert_true(steam.available())
	var me: String = str(steam.steam_id)
	var run: RunState = RunState.create(1, ServerConfig.Mode.FRIENDS, false)
	var server_t: SdrTransport = SdrTransport.new(api)
	assert_eq(server_t.listen("", 40), OK)
	var net: ServerNet = ServerNet.new(server_t, 5)
	ServerSystems.install(run, net)
	var client: ClientConnection = ClientConnection.new(SdrTransport.new(api))
	client.identity = me
	assert_true(client.start(me, 40))
	var waited: int = 0
	while client.state != ClientConnection.State.CONNECTED and waited < 600:
		await get_tree().process_frame
		client.poll()
		run.run_tick()
		waited += 1
	gut.p("connected after %d frames; relays %s" % [waited, steam.relay_text()])
	assert_eq(client.state, ClientConnection.State.CONNECTED, "NET-02's handshake over Steam Networking Sockets")
	var server_peer: int = server_t.peers()[0] if not server_t.peers().is_empty() else -1
	assert_eq(server_t.verified_identity(server_peer), me, "Steam's authenticated SteamID")
	var flags: int = 0
	for h: Variant in Variants.dict(server_t._handles).keys():
		var info: Dictionary = api.sns_info(Variants.whole(h))
		flags |= Variants.whole(info.get("info_flags", 0))
		gut.p("connection info: %s" % [info])
	assert_eq(flags & (SteamApi.SNS_INFO_UNAUTHENTICATED | SteamApi.SNS_INFO_UNENCRYPTED), 0, "authenticated and encrypted")
	# A second client claiming another SteamID.
	var liar: ClientConnection = ClientConnection.new(SdrTransport.new(api))
	liar.identity = "76561198000000001"
	assert_true(liar.start(me, 40))
	waited = 0
	while liar.state != ClientConnection.State.REJECTED and liar.state != ClientConnection.State.CONNECTED and waited < 600:
		await get_tree().process_frame
		liar.poll()
		client.poll()
		run.run_tick()
		waited += 1
	assert_eq(liar.state, ClientConnection.State.REJECTED)
	assert_eq(liar.reject_reason, Protocol.Reject.AUTH_FAILED, "a Hello as another SteamID: auth_failed")
	liar.close()
	# Every lane, server to client, on the raw transports.
	var client_t: SdrTransport = client.transport as SdrTransport
	var client_peer: int = client_t.peers()[0]
	for lane: int in Lane.COUNT:
		assert_eq(client_t.send(client_peer, lane, PackedByteArray([200 + lane])), OK)
	client_t.flush()
	var lanes: Dictionary = {}
	waited = 0
	while lanes.size() < Lane.COUNT and waited < 300:
		await get_tree().process_frame
		for e: TransportEvent in server_t.poll():
			if e.kind == TransportEvent.Kind.MESSAGE and e.data.size() == 1 and e.data[0] == 200 + e.lane:
				lanes[e.lane] = true
		waited += 1
	assert_eq(lanes.size(), Lane.COUNT, "all six lanes over Steam")
	gut.p("rtt %.1f ms, loss %.3f" % [server_t.stats(server_peer).rtt_ms, server_t.stats(server_peer).loss])
	# A 2 MB bulk transfer does not hold voice back: voice sent with it arrives within one tick.
	var chunk: PackedByteArray = PackedByteArray()
	chunk.resize(64 * 1024)
	for _i: int in 32:
		client_t.send(client_peer, Lane.Id.BULK, chunk)
	for v: int in 5:
		client_t.send(client_peer, Lane.Id.VOICE, PackedByteArray([250, v]))
	client_t.flush()
	var voice_at: int = -1
	var bulk_bytes: int = 0
	var frame: int = 0
	while (voice_at < 0 or bulk_bytes < 2 * 1024 * 1024) and frame < 600:
		await get_tree().process_frame
		frame += 1
		for e: TransportEvent in server_t.poll():
			if e.kind != TransportEvent.Kind.MESSAGE:
				continue
			if e.lane == Lane.Id.VOICE and voice_at < 0:
				voice_at = frame
			elif e.lane == Lane.Id.BULK:
				bulk_bytes += e.data.size()
	gut.p("2 MB bulk: voice arrived at frame %d; bulk complete %d bytes by frame %d" % [voice_at, bulk_bytes, frame])
	assert_between(voice_at, 1, 2, "voice within a tick of being sent, behind nothing")
	assert_eq(bulk_bytes, 2 * 1024 * 1024, "the bulk arrived whole")
	# Closing: the server drops the client once.
	client_t.disconnect_peer(client_peer)
	var drops: int = 0
	waited = 0
	while waited < 300:
		await get_tree().process_frame
		for e: TransportEvent in server_t.poll():
			if e.kind == TransportEvent.Kind.DROPPED:
				drops += 1
		waited += 1
		if drops > 0 and waited > 60:
			break
	assert_eq(drops, 1, "one dropped for the three connections")
	server_t.close()
	client_t.close()
	await get_tree().process_frame
	steam.shutdown()
