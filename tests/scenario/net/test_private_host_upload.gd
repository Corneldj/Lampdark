extends GutTest
## STM-04: a private host's upload budget (GDD §15.10: about 2 Mbps). A real server on GEN-03's
## populated grey box serves four clients over ENet on loopback (the ticket's proxy for SDR), each
## behind a UDP link emulator that counts the server's datagrams to it. For 20 s all four move and talk
## (talk band, 50 frames a second of 60 bytes, every speaker heard by the others: worse than play).
## The server's total upload, IPv4 and UDP headers included, stays at or under
## net.private_host_upload_kbps at the 95th percentile of one-second windows.

const Emulator = preload("res://tests/support/udp_link_emulator.gd")
const MAP: String = "m1_greybox"
const SECONDS: float = 20.0


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_four_busy_clients_stay_under_the_budget() -> void:
	var server: EnetTransport = EnetTransport.new()
	assert_eq(server.listen("127.0.0.1", 0), OK)
	var run: RunState = RunState.create(7, ServerConfig.Mode.FRIENDS, false)
	var mine: Mine = Mine.new()
	assert_gt(FixedMapLoader.load_cells(mine, MAP), 0)
	var net: ServerNet = ServerNet.new(server, 5)
	ServerSystems.install(run, net, mine)
	FixedMapLoader.populate(run, MAP, true, true)
	var links: Array[Emulator] = []
	var clients: Array[ClientConnection] = []
	for i: int in 4:
		var link: Emulator = Emulator.new()
		var port: int = link.start(server.bound_port())
		var c: ClientConnection = ClientConnection.new(EnetTransport.new())
		c.identity = "bot%d" % i
		assert_true(c.start("127.0.0.1", port))
		links.append(link)
		clients.append(c)
	# No server code spawns a joining miner yet (GEN-03: MOD and LFT own it), so the test places the
	# four on base camp's floor as the scenario kit does, once each client is welcomed.
	var placed: Array[bool] = [false, false, false, false]
	var inside: Array = Basecamp.inside_tiles(FixedMapLoader.run_seed(FixedMapLoader.manifest(MAP)),
		FixedMapLoader.blind_side(FixedMapLoader.manifest(MAP))).keys()
	inside.sort()
	var spots: Array[Vector2i] = []
	for raw: Variant in inside:
		var t: Vector2i = raw
		var last: Vector2i = spots.back() if not spots.is_empty() else Vector2i(-99, -99)
		if mine.native.is_walkable(t) and Vector2(t).distance_to(Vector2(last)) > 2.5:
			spots.append(t)
		if spots.size() == 4:
			break
	var tick_usec: int = 50000
	var next_tick: int = Time.get_ticks_usec()
	var next_voice: int = Time.get_ticks_usec()
	var n: int = 0
	var seq: Array[int] = [0, 0, 0, 0]
	var filler: PackedByteArray = PackedByteArray()
	filler.resize(60)
	var windows: Array[float] = []
	var window_start: int = -1
	var window_bytes: int = 0
	var end_usec: int = -1
	while true:
		var now: int = Time.get_ticks_usec()
		for l: Emulator in links:
			l.pump(now)
		for c: ClientConnection in clients:
			c.poll()
		for i: int in 4:
			if not placed[i] and clients[i].state == ClientConnection.State.CONNECTED:
				placed[i] = true
				var slot: int = clients[i].welcome.slot
				var e: SimEntity = run.registry.create(WorldIds.EntityKind.MINER, Vector2(spots[i]) + Vector2(0.5, 0.5))
				run.movement.add_miner(slot, e.id, e.position, 0)
				run.miner_state.add_miner(e.id, slot)
				run.vision.watch(slot, e.id, 0)
		var all_up: bool = clients.all(func(c: ClientConnection) -> bool: return c.state == ClientConnection.State.CONNECTED)
		if now >= next_tick:
			next_tick += tick_usec
			run.run_tick()
			n += 1
			if all_up:
				for i: int in 4:
					var r: InputRecord = InputRecord.new()
					r.facing = ((n + i * 4000) * 997) & 0xFFFF
					r.move_dir = ((n / 5 + i * 9) * 31) % 255
					r.gait = InputRecord.Gait.WALK
					clients[i].inputs.send_tick(clients[i], r, clients[i].last_frame_tick)
		if all_up and now >= next_voice:
			next_voice += 20000
			for i: int in 4:
				if clients[i].send_voice(VoicePackets.up(seq[i] & 0xFFFF, 2, 0, filler)) == OK:
					seq[i] += 1
		if all_up and window_start < 0:
			window_start = now
			end_usec = now + roundi(SECONDS * 1000000.0)
			window_bytes = _down_bytes(links)
		elif window_start >= 0 and now - window_start >= 1000000:
			var total: int = _down_bytes(links)
			windows.append((total - window_bytes) * 8.0 / ((now - window_start) / 1000000.0) / 1000.0)
			window_bytes = total
			window_start = now
		if end_usec > 0 and now >= end_usec:
			break
		if end_usec < 0 and n > 400:
			break
		OS.delay_usec(1000)
	assert_gt(windows.size(), 15, "a 20 s busy window, all four connected")
	var sorted: Array[float] = windows.duplicate()
	sorted.sort()
	var at: int = mini(sorted.size() - 1, ceili(sorted.size() * 0.95) - 1)
	var p95: float = sorted[at] if not sorted.is_empty() else 0.0
	var mean: float = 0.0
	for w: float in windows:
		mean += w / windows.size()
	var budget: float = Tuning.f(&"net.private_host_upload_kbps")
	gut.p("server upload over %d s: mean %.0f kbps, p95 %.0f kbps (budget %.0f); voice frames each %s" % [windows.size(), mean, p95, budget, seq])
	var miners: Array[String] = []
	for id: int in run.registry.ids():
		var e: SimEntity = run.registry.get_entity(id)
		if e.kind == WorldIds.EntityKind.MINER:
			miners.append(str(e.position))
	gut.p("voice: forwarded %d, dropped %d, refused %d; miners %s" % [run.voice.forwarded, run.voice.dropped, run.voice.refused, miners])
	assert_gt(run.voice.forwarded, 4 * 3 * 50 * 10, "every speaker heard by the other three throughout")
	assert_lte(p95, budget, "p95 at or under net.private_host_upload_kbps")
	for c: ClientConnection in clients:
		c.close()
	for l: Emulator in links:
		l.close()
	server.close()


func _down_bytes(links: Array[Emulator]) -> int:
	var total: int = 0
	for l: Emulator in links:
		total += l.server_bytes + 28 * l.server_datagrams
	return total
