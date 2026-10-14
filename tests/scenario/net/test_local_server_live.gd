extends GutTest
## STM-04's Path A live (manual: LB_STEAM_LIVE=1 with Steam running, from game/, after exporting
## linux-server-qa; pending otherwise and in CI). The host's client spawns the exported server, which
## loads GodotSteam Server at run time, logs on as an anonymous unlisted game server and listens on SDR
## under its own SteamID; the client, admitted as the lobby's owner, completes NET-02's handshake over a
## relayed connection; the server binds nothing beyond loopback but Steam's own sockets; a clean stop
## exits 0.

const EXPORT: String = "res://build/linux-server-qa/lampblack_server.x86_64"


## One Steam session for the file: GodotSteam cannot bring Steam up again in a process once it is down.
var api: SteamApi = null
var steam: SteamService = null


func before_all() -> void:
	assert_true(Tuning.load_server())
	if OS.get_environment("LB_STEAM_LIVE") == "1":
		api = SteamApi.new()
		steam = SteamService.new(api)
		add_child(steam)
		assert_eq(steam.boot(false, false, ""), SteamService.Boot.CONTINUE)


func after_all() -> void:
	if steam != null:
		steam.shutdown()
		steam.queue_free()


func _wait(cond: Callable, seconds: float) -> bool:
	var until: int = Time.get_ticks_msec() + roundi(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		if Variants.flag(cond.call()):
			return true
		await get_tree().process_frame
	return Variants.flag(cond.call())


func test_path_a_over_steam() -> void:
	if OS.get_environment("LB_STEAM_LIVE") != "1" or not FileAccess.file_exists(EXPORT):
		pending("manual: LB_STEAM_LIVE=1 with Steam running and linux-server-qa exported")
		return
	var host: LocalServerHost = LocalServerHost.new()
	host.executable_override = ProjectSettings.globalize_path(EXPORT)
	add_child_autofree(host)
	var t0: int = Time.get_ticks_msec()
	assert_true(host.start(LocalServerHost.Path.A))
	assert_true(await _wait(func() -> bool: return host.state == LocalServerHost.State.READY, 30.0), "ready, logged on")
	var server_id: int = Variants.whole(host.info["identity"])
	gut.p("Path A ready in %d ms: game server %d" % [Time.get_ticks_msec() - t0, server_id])
	assert_gt(server_id, 0, "its own game-server SteamID")
	host.send_members(steam.steam_id, PackedInt64Array([steam.steam_id]), PackedInt64Array(), PackedInt64Array())
	await get_tree().create_timer(0.5).timeout
	var client: ClientConnection = ClientConnection.new(SdrTransport.new(api))
	client.identity = str(steam.steam_id)
	assert_true(client.start(str(server_id), Variants.whole(host.info["vport"])))
	var c0: int = Time.get_ticks_msec()
	assert_true(await _wait(func() -> bool:
		client.poll()
		return client.state == ClientConnection.State.CONNECTED or client.state == ClientConnection.State.REJECTED, 30.0))
	gut.p("handshake over SDR in %d ms; state %s" % [Time.get_ticks_msec() - c0, ClientConnection.State.keys()[client.state]])
	assert_eq(client.state, ClientConnection.State.CONNECTED, "NET-02's handshake with the game server, over Steam")
	var t: SdrTransport = client.transport as SdrTransport
	var relayed: int = 0
	for h: Variant in Variants.dict(t._handles).keys():
		var info: Dictionary = api.sns_info(Variants.whole(h))
		gut.p("client connection: %s" % [info.get("debug_description", "")])
		if (Variants.whole(info.get("info_flags", 0)) & SteamApi.SNS_INFO_RELAYED) != 0:
			relayed += 1
	assert_eq(relayed, SdrTransport.GROUPS, "all three connections relayed")
	await _wait(func() -> bool:
		client.poll()
		return client.frames_received > 20, 10.0)
	assert_gt(client.frames_received, 20, "frames arrive over the relay")
	gut.p("rtt %.0f ms, frames %d" % [client.transport.stats(t.peers()[0]).rtt_ms, client.frames_received])
	var out: Array = []
	OS.execute("ss", PackedStringArray(["-lnup"]), out, true)
	var binds: PackedStringArray = PackedStringArray()
	for line: String in "".join(PackedStringArray(out)).split("\n"):
		if line.contains("pid=%d," % host.pid):
			binds.append(line.split(" ", false)[3] if line.split(" ", false).size() > 3 else line)
	gut.p("the server's UDP sockets: %s" % [binds])
	var wide: int = 0
	for b: String in binds:
		var loopback: bool = b.begins_with("127.0.0.1:") or b.begins_with("[::ffff:127.0.0.1]:")
		if not loopback:
			wide += 1  # the game-server API's own relay socket (steamclient, inside the process)
	assert_eq(binds.size() - wide, 2, "ours: the game port and the host link, both on loopback")
	assert_lte(wide, 1, "beyond loopback only Steam's own socket")
	var ends: Array[Array] = []
	host.ended.connect(func(code: int, crashed: bool) -> void: ends.append([code, crashed]))
	client.close()
	host.stop()
	assert_true(await _wait(func() -> bool: return not ends.is_empty(), 15.0))
	assert_eq(ends[0], [0, false], "a clean stop")


func test_path_b_over_steam() -> void:
	# Path B live: a source-run server (no Steam of its own), the host relay holding SDR under the
	# user's SteamID, and a friend reaching it (Steam's pipe, one account) through the relay and its
	# tag; the friend's round trip through the relay against the host's direct one over loopback.
	if OS.get_environment("LB_STEAM_LIVE") != "1":
		pending("manual: LB_STEAM_LIVE=1 with Steam running")
		return
	var host: LocalServerHost = LocalServerHost.new()
	add_child_autofree(host)
	assert_true(host.start(LocalServerHost.Path.B))
	assert_true(await _wait(func() -> bool: return host.state == LocalServerHost.State.READY, 30.0))
	var relay: HostRelay = HostRelay.new(SdrTransport.new(api), Variants.whole(host.info["game"]), str(host.info["token"]))
	assert_eq(relay.listen(50), OK)
	var direct: ClientConnection = ClientConnection.new(EnetTransport.new())
	direct.identity = "host-direct"
	direct.start("127.0.0.1", Variants.whole(host.info["game"]))
	var friend: ClientConnection = ClientConnection.new(SdrTransport.new(api))
	friend.identity = str(steam.steam_id)
	assert_true(friend.start(str(steam.steam_id), 50))
	assert_true(await _wait(func() -> bool:
		relay.poll()
		friend.poll()
		direct.poll()
		return friend.state == ClientConnection.State.CONNECTED and direct.state == ClientConnection.State.CONNECTED, 30.0))
	assert_eq(friend.state, ClientConnection.State.CONNECTED, "through the relay, the tag matching the Hello")
	await _wait(func() -> bool:
		relay.poll()
		friend.poll()
		direct.poll()
		return false, 6.0)
	gut.p("round trip: through the relay %.1f ms, direct %.1f ms; relayed messages %d" % [friend.clock.rtt_ms(), direct.clock.rtt_ms(), relay.relayed])
	assert_gt(relay.relayed, 50)
	friend.close()
	direct.close()
	relay.close()
	host.stop()
	assert_true(await _wait(func() -> bool: return host.state == LocalServerHost.State.ENDED, 15.0))
