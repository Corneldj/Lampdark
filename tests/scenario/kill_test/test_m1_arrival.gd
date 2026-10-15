extends GutTest
## QA-01's minimal M1 arrival (MOD-04 replaces it): on a real server with GEN-03's grey box, each
## welcomed player gets a miner on base camp's cage deck (else its floor), a tile apart, and sees it as
## its own miner in its stream; a rejoin gets no second miner. And a real server process with --map
## m1_greybox gives a connecting client its miner, as the kill test's studio server will.

const MAP: String = "m1_greybox"


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_five_arrive_in_base_camp_and_see_themselves() -> void:
	var hub: InProcessTransport.Hub = InProcessTransport.Hub.new()
	var t: InProcessTransport = InProcessTransport.new(hub)
	t.listen("s", 1)
	var run: RunState = RunState.create(11, ServerConfig.Mode.FRIENDS, false)
	var mine: Mine = Mine.new()
	assert_gt(FixedMapLoader.load_cells(mine, MAP), 0)
	var net: ServerNet = ServerNet.new(t, 5)
	ServerSystems.install(run, net, mine)
	FixedMapLoader.populate(run, MAP, true, true)
	var arrival: M1Arrival = M1Arrival.new(run, mine)
	net.welcomed.connect(arrival.on_welcomed)
	var clients: Array[ClientConnection] = []
	for i: int in 5:
		var c: ClientConnection = ClientConnection.new(InProcessTransport.new(hub))
		c.identity = "miner%d" % i
		c.start("s", 1)
		clients.append(c)
	for _i: int in 20:
		for c: ClientConnection in clients:
			c.poll()
		run.run_tick()
	assert_eq(arrival.miners.size(), 5, "five miners")
	var deck: Rect2i = Basecamp.deck_rect(run.base_camp.seed_value, run.base_camp.side)
	var spots: Array[Vector2] = []
	for raw: Variant in arrival.miners.values():
		var e: SimEntity = run.registry.get_entity(Variants.whole(raw))
		spots.append(e.position)
		assert_true(run.base_camp.inside_tiles.has(Vector2i(e.position.floor())), "in base camp: %s" % e.position)
	var on_deck: int = spots.filter(func(p: Vector2) -> bool: return deck.has_point(Vector2i(p.floor()))).size()
	gut.p("arrived at %s; %d on the cage deck %s" % [spots, on_deck, deck])
	assert_gt(on_deck, 0, "the cage deck first")
	for i: int in spots.size():
		for j: int in range(i + 1, spots.size()):
			assert_gte(spots[i].distance_to(spots[j]), M1Arrival.SPACING - 1e-6, "a tile apart")
	for c: ClientConnection in clients:
		assert_false(c.view.own.is_empty(), "%s sees its own miner" % c.identity)
		var own: Vector2 = c.view.own.get("position", Vector2.ZERO)
		var e: SimEntity = run.registry.get_entity(Variants.whole(arrival.miners[c.identity]))
		assert_lt(own.distance_to(e.position), 0.05, "where the server put it")
	# A rejoin as the same identity: no second miner (NET-11 hands back the first).
	clients[0].close()
	for _i: int in 10:
		run.run_tick()
	var back: ClientConnection = ClientConnection.new(InProcessTransport.new(hub))
	back.identity = "miner0"
	back.start("s", 1)
	for _i: int in 20:
		back.poll()
		run.run_tick()
	var count: int = 0
	for id: int in run.registry.ids():
		if run.registry.get_entity(id).kind == WorldIds.EntityKind.MINER:
			count += 1
	assert_eq(count, 5, "no second miner for a returning identity")


func test_a_real_server_with_the_grey_box_gives_a_client_its_miner() -> void:
	var port: int = 28000 + randi() % 2000
	var pid: int = OS.create_process(OS.get_executable_path(), PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--", "--server", "--map", MAP, "--port", str(port), "--exit-after-ticks", "600"]))
	assert_gt(pid, 0)
	var c: ClientConnection = ClientConnection.new(EnetTransport.new())
	c.identity = "kill-tester"
	var started: bool = false
	var until: int = Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < until:
		if not started:
			await get_tree().create_timer(1.0).timeout
			started = c.start("127.0.0.1", port)
			continue
		c.poll()
		# A slow start (the server under Wine takes about 6 s to listen) outlasts one handshake: try
		# again, as a player's client would.
		if c.state == ClientConnection.State.DROPPED and c.frames_received == 0:
			c.close()
			c = ClientConnection.new(EnetTransport.new())
			c.identity = "kill-tester"
			started = false
			continue
		if c.state == ClientConnection.State.CONNECTED and not c.view.own.is_empty() and c.frames_received > 10:
			break
		await get_tree().process_frame
	gut.p("own miner at %s after %d frames" % [c.view.own.get("position", "none"), c.frames_received])
	assert_eq(c.state, ClientConnection.State.CONNECTED)
	assert_false(c.view.own.is_empty(), "the server gave the kill tester a miner")
	c.close()
	if OS.is_process_running(pid):
		OS.kill(pid)
