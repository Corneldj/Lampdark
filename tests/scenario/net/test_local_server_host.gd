extends GutTest
## STM-04 with real processes: LocalServerHost spawns this project's server (a source run: Path B's
## loopback server), reads its ready line within net.local_server_ready_timeout_s, and the host's
## client completes NET-02's handshake over loopback; a clean stop exits 0 with no process left; a
## killed server is noticed within 1 s; a server whose last client left goes after the linger (the
## test_hosting profile: 2 s); a restarted client reattaches through the lock; Night Shift's offline
## spawn has no Steam identity. MOD-03: the hosted run waits at the Pithead, seating its crew and
## sending no game data, until the host's start creates it (a refused start says why, and the crew
## stays at the Pithead).

var _hosts: Array[LocalServerHost] = []


func before_all() -> void:
	assert_true(Tuning.load_client())


func after_each() -> void:
	for h: LocalServerHost in _hosts:
		if h.pid > 0 and Variants.flag(ClassDB.class_call_static(&"LbCoreInfo", &"process_alive", h.pid)):
			OS.kill(h.pid)
	_hosts.clear()


func _host(which: LocalServerHost.Path = LocalServerHost.Path.B) -> LocalServerHost:
	var h: LocalServerHost = LocalServerHost.new()
	h.extra_args = PackedStringArray(["--tuning-profile", "test_hosting"])
	add_child_autofree(h)
	_hosts.append(h)
	assert_true(h.start(which), "spawned")
	return h


func _wait(cond: Callable, seconds: float) -> bool:
	var until: int = Time.get_ticks_msec() + roundi(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		if Variants.flag(cond.call()):
			return true
		await get_tree().process_frame
	return Variants.flag(cond.call())


func _join(h: LocalServerHost) -> ClientConnection:
	var c: ClientConnection = ClientConnection.new(EnetTransport.new())
	c.identity = "76561198030964382"
	assert_true(c.start("127.0.0.1", Variants.whole(h.info["game"])))
	await _wait(func() -> bool:
		c.poll()
		return c.state == ClientConnection.State.CONNECTED, 10.0)
	return c


func test_ready_join_and_a_clean_stop() -> void:
	var h: LocalServerHost = _host()
	var t0: int = Time.get_ticks_msec()
	assert_true(await _wait(func() -> bool: return h.state == LocalServerHost.State.READY, Tuning.f(&"net.local_server_ready_timeout_s")),
		"the ready line within net.local_server_ready_timeout_s")
	gut.p("ready in %d ms: %s" % [Time.get_ticks_msec() - t0, h.info])
	assert_gt(Variants.whole(h.info["game"]), 0)
	assert_eq(Variants.whole(h.info["identity"]), 0, "Path B's server has no Steam identity of its own")
	assert_true(FileAccess.file_exists(LocalServerHost.LOCK_PATH), "the lock for a reattach")
	var statuses: Array[Dictionary] = []
	h.link_status.connect(func(st: Dictionary) -> void: statuses.append(st))
	var c: ClientConnection = await _join(h)
	assert_eq(c.state, ClientConnection.State.CONNECTED, "the host joins its own server like any client")
	assert_true(await _wait(func() -> bool: return not statuses.is_empty(), 5.0), "the control link answers")
	var ends: Array[Array] = []
	h.ended.connect(func(code: int, crashed: bool) -> void: ends.append([code, crashed]))
	var pid: int = h.pid
	h.stop()
	assert_true(await _wait(func() -> bool: return not ends.is_empty(), 10.0), "stopped")
	assert_eq(ends[0], [0, false], "exit 0, no crash")
	assert_false(Variants.flag(ClassDB.class_call_static(&"LbCoreInfo", &"process_alive", pid)), "no process left")
	assert_false(FileAccess.file_exists(LocalServerHost.LOCK_PATH))
	c.close()


func test_the_run_begins_at_the_hosts_start() -> void:
	var h: LocalServerHost = _host()
	assert_true(await _wait(func() -> bool: return h.state == LocalServerHost.State.READY, Tuning.f(&"net.local_server_ready_timeout_s")))
	var c: ClientConnection = await _join(h)
	assert_eq(c.state, ClientConnection.State.CONNECTED, "seated at the Pithead")
	await _wait(func() -> bool:
		c.poll()
		return false, 1.0)
	assert_eq(c.frames_received, 0, "at the Pithead nothing ticks and nothing is sent")
	var refusals: Array[String] = []
	var starts: Array[bool] = []
	h.start_refused.connect(func(reason: String) -> void: refusals.append(reason))
	h.run_started.connect(func() -> void: starts.append(true))
	h.send_start({"mode": "friends", "list": "standard", "hard": "one_lamp", "hands": false}, false)
	assert_true(await _wait(func() -> bool:
		c.poll()
		return not refusals.is_empty(), 10.0), "a variant the host has not unlocked is refused")
	gut.p("refused: %s" % refusals)
	assert_false(refusals[0].is_empty(), "in plain words")
	assert_true(starts.is_empty())
	assert_eq(c.frames_received, 0, "still at the Pithead")
	var with_hands: RunOptions = RunOptions.defaults(ServerConfig.Mode.FRIENDS)
	with_hands.hands_in_empty_places = true
	h.send_start(with_hands.to_dict(), false)
	assert_true(await _wait(func() -> bool:
		c.poll()
		return not starts.is_empty(), 20.0), "the run begins")
	assert_true(await _wait(func() -> bool:
		c.poll()
		return c.frames_received > 10, 10.0), "frames once it has begun")
	gut.p("frames %d after the start" % c.frames_received)
	h.stop()
	assert_true(await _wait(func() -> bool: return h.state == LocalServerHost.State.ENDED, 10.0))
	c.close()
	# MOD-08: the host chose Hands, so Hired Hands filled the four empty places at the start.
	var server_log: String = FileAccess.get_file_as_string(h.log_path)
	for line: String in server_log.split("\n"):
		if line.contains("hands") or line.contains("arrival") or line.contains("run created"):
			gut.p(line)
	assert_true(server_log.contains("hands: 4 Hired Hands fill the empty places"), "Hands in the empty places")


func test_a_killed_server_is_noticed_within_a_second() -> void:
	var h: LocalServerHost = _host()
	assert_true(await _wait(func() -> bool: return h.state == LocalServerHost.State.READY, 20.0))
	var ends: Array[Array] = []
	var noticed_ms: Array[int] = [0]
	h.ended.connect(func(code: int, crashed: bool) -> void:
		ends.append([code, crashed])
		noticed_ms[0] = Time.get_ticks_msec())
	var killed_ms: int = Time.get_ticks_msec()
	if OS.get_name() == "Windows":
		OS.kill(h.pid)
	else:
		OS.execute("kill", PackedStringArray(["-9", str(h.pid)]))  # a crash from outside, as a real one comes
	assert_true(await _wait(func() -> bool: return not ends.is_empty(), 3.0))
	gut.p("noticed %d ms after the kill; ended %s" % [noticed_ms[0] - killed_ms, ends])
	assert_lt(noticed_ms[0] - killed_ms, 1000, "within 1 s")
	assert_true(Variants.flag(Variants.array(ends[0])[1]), "a crash")


func test_the_last_client_leaving_ends_the_server_after_the_linger() -> void:
	var h: LocalServerHost = _host()
	assert_true(await _wait(func() -> bool: return h.state == LocalServerHost.State.READY, 20.0))
	var c: ClientConnection = await _join(h)
	assert_eq(c.state, ClientConnection.State.CONNECTED)
	await get_tree().create_timer(0.5).timeout
	var ends: Array[Array] = []
	h.ended.connect(func(code: int, crashed: bool) -> void: ends.append([code, crashed]))
	var left_ms: int = Time.get_ticks_msec()
	c.close()
	assert_true(await _wait(func() -> bool: return not ends.is_empty(), 15.0), "the server went on its own")
	var after: float = (Time.get_ticks_msec() - left_ms) / 1000.0
	gut.p("ended %.1f s after the last client left" % after)
	assert_between(after, 1.5, 8.0, "after net.empty_server_linger_s (2 s in test_hosting)")
	assert_eq(ends[0], [0, false], "a clean exit")


func test_a_restarted_client_reattaches() -> void:
	var first: LocalServerHost = _host()
	assert_true(await _wait(func() -> bool: return first.state == LocalServerHost.State.READY, 20.0))
	var pid: int = first.pid
	first.forget()  # the client crashed: its server runs on
	await get_tree().create_timer(1.5).timeout
	assert_true(Variants.flag(ClassDB.class_call_static(&"LbCoreInfo", &"process_alive", pid)), "the server outlived its client")
	var second: LocalServerHost = LocalServerHost.new()
	add_child_autofree(second)
	_hosts.append(second)
	var statuses: Array[Dictionary] = []
	second.link_status.connect(func(st: Dictionary) -> void: statuses.append(st))
	assert_true(second.reattach(), "reattached from the lock")
	assert_eq(second.pid, pid)
	assert_true(await _wait(func() -> bool: return not statuses.is_empty(), 5.0), "the control link answers the restarted client")
	second.stop()
	assert_true(await _wait(func() -> bool: return not Variants.flag(ClassDB.class_call_static(&"LbCoreInfo", &"process_alive", pid)), 10.0))


func test_night_shift_spawns_offline_with_no_steam() -> void:
	var h: LocalServerHost = _host(LocalServerHost.Path.OFFLINE)
	assert_true(await _wait(func() -> bool: return h.state == LocalServerHost.State.READY, 20.0))
	assert_eq(Variants.whole(h.info["identity"]), 0, "no Steam identity")
	var cmd: Dictionary = LocalServerHost.command(LocalServerHost.Path.OFFLINE, "x.log")
	var args: PackedStringArray = cmd["args"]
	assert_true(args.has("--offline") and args.has("--loopback") and not args.has("--transport"), "offline, loopback, no SDR")
	h.stop()
	assert_true(await _wait(func() -> bool: return h.state == LocalServerHost.State.ENDED, 10.0))
	var log_text: String = FileAccess.get_file_as_string(h.log_path)
	assert_false(log_text.contains("game server") or log_text.contains("SDR"), "nothing of Steam in its log")
	assert_true(log_text.contains("listening on 127.0.0.1:"), "loopback only")
