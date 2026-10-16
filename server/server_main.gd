extends Node
## The headless server entry (FND-03). It loads tuning (FND-05), builds the RunState and
## drives NET-01's SimLoop from the monotonic clock, sleeping to each 50 ms deadline.
## The transport (NET-02) registers into stage 1 when it exists.

## Log tick-rate statistics this often, in ticks (60 s at 20 Hz).
const STATS_EVERY_TICKS: int = 1200
## NET-08: the stream audit, loaded by path in dev and QA servers only (tools/ is not in a pack).
const STREAM_AUDIT: String = "res://tools/stream_audit/stream_audit.gd"

## STM-02: dev-mode lobbies, outside release builds only.
var rendezvous: LobbyRendezvous = null
## STM-04: a private host's server (spawned with --parent-pid): its control link, Path A's game-server
## Steam (GodotSteam Server, loaded at run time) and SDR listener, and the empty-server linger.
var host_link: HostLink = null
## QA-01: a welcomed player's miner, on servers with a map.
var arrival: M1Arrival = null
## GEN-11: a generated mine's lazy generation (--generate).
var generation: Generation = null
var steam_server: SteamServerApi = null
var sdr: SdrTransport = null
var _game_port: int = 0
var _ready_printed: bool = false
var _had_client: bool = false
var _empty_since_usec: int = -1
var _finishing: bool = false
var config: ServerConfig = null
var run: RunState = null
var loop: SimLoop = null
var net: ServerNet = null
var _started_usec: int = 0
var _last_stats_tick: int = 0
## FND-08: the server console reads stdin on its own thread (dev and QA, a terminal only).
var _console_thread: Thread = null
var _audit: RefCounted = null
## NET-09: the save this server resumes (`--resume`), opened; empty for a new run.
var _resume: Dictionary = {}


func start(server_config: ServerConfig) -> void:
	config = server_config
	if not Tuning.load_server(config.tuning_profile):
		Log.error("tuning failed to load; see the errors above")
		get_tree().quit(ExitCode.FATAL)
		return
	Tuning.enable_hot_reload(config.build.allows_tuning_hot_reload(config.tuning_hot_reload))
	Log.info("tuning loaded: %d keys, hash %s%s" % [Tuning.current.entries.size(),
		Tuning.content_hash().left(12), ", hot reload on" if Tuning.is_polling() else ""])
	# A dedicated-server export runs headless: no window, no audio device (GDD §15.1).
	Log.info("display=%s audio=%s" % [DisplayServer.get_name(), AudioServer.get_driver_name()])

	if not config.map_name.is_empty() and FixedMapLoader.manifest(config.map_name).is_empty():
		Log.error("no fixed map named '%s' (data/maps/%s/manifest.json)" % [config.map_name, config.map_name])
		get_tree().quit(ExitCode.BAD_ARGUMENTS)
		return
	if not config.resume_path.is_empty():
		_resume = SaveResume.open_file(config.resume_path)
		if not Variants.flag(_resume["ok"]):
			Log.error("cannot resume %s: %s" % [config.resume_path, str(_resume["message"])])
			get_tree().quit(ExitCode.VERSION_MISMATCH if str(_resume["error"]) == SaveResume.ERR_VERSIONS else ExitCode.BAD_ARGUMENTS)
			return
		var head: Dictionary = _resume["head"]
		config.mode = int(Variants.number(head["mode"])) as ServerConfig.Mode
		config.offline = Variants.flag(head.get("offline", false))
		config.map_name = str(head.get("map_name", ""))
		run = RunState.create(int(Variants.number(head["run_seed"])), config.mode, config.offline)
	else:
		run = RunState.create(_run_seed(), config.mode, config.offline)
		if run != null:
			run.header.run_uuid = _new_run_uuid()
	if run != null:
		run.header.map_name = config.map_name
	if run == null or not run.startup_errors().is_empty():
		Log.error("the run could not be created")
		get_tree().quit(ExitCode.FATAL)
		return
	Log.dev("run seed %s" % LbHash.to_hex(run.header.run_seed))
	if not _start_network():
		return
	loop = SimLoop.new(run)
	loop.stop_after_ticks = config.exit_after_ticks
	if ClassDB.class_exists(&"LbCoreInfo"):
		ClassDB.class_call_static(&"LbCoreInfo", &"request_timer_resolution_1ms")
	Log.info("server starting: mode=%s transport=%s port=%d offline=%s tick=%d us" % [
		ServerConfig.Mode.keys()[config.mode], ServerConfig.TransportKind.keys()[config.transport],
		config.port, run.header.offline, loop.tick_usec])
	_started_usec = TickTimer.now_usec()
	loop.start(_started_usec)
	set_process(true)


func _ready() -> void:
	set_process(false)


func _process(_delta: float) -> void:
	if steam_server != null:
		steam_server.run_callbacks()
	if host_link != null:
		host_link.poll()
		_linger()
	loop.pump(TickTimer.now_usec())
	if rendezvous != null:
		rendezvous.poll()
	if run.tick - _last_stats_tick >= STATS_EVERY_TICKS:
		_last_stats_tick = run.tick
		_log_stats()
	if loop.is_done():
		Log.info("exit after %d ticks" % loop.ticks_run)
		_log_stats()
		_finish_records()
		# NET-09: the run ends unfinished, as at any other server end: saved (or voided in public),
		# after the final state hash (FND-09's replay ends where the run did).
		if run.saves != null:
			run.saves.end_abnormally(run, "exit after %d ticks" % loop.ticks_run)
		Log.close()
		get_tree().quit(ExitCode.OK)
		return
	# Sleep to the next deadline in slices of at most 1 ms, servicing the network between them.
	var wait: int = loop.usec_until_next(TickTimer.now_usec())
	while wait > 0:
		OS.delay_usec(mini(wait, 1000))
		net.service()
		wait = loop.usec_until_next(TickTimer.now_usec())


## Listens with the chosen transport and registers the network stages (NET-02). SDR arrives
## with STM-03. Release builds bind ENet only to 127.0.0.1.
func _start_network() -> bool:
	var hosted: bool = config.parent_pid > 0
	var transport: EnetTransport = EnetTransport.new()
	transport.build = config.build
	# A private host's server takes any free loopback port (the ready line names it).
	var port: int = config.port if config.port > 0 else (0 if hosted else Tuning.i(&"net.dev_port"))
	var loopback: bool = hosted or config.transport != ServerConfig.TransportKind.ENET or config.build.is_release()
	var bind_address: String = "127.0.0.1" if loopback else "*"
	var error: Error = transport.listen(bind_address, port)
	if error != OK:
		Log.error("could not listen on %s:%d (%s)" % [bind_address, port, error_string(error)])
		get_tree().quit(ExitCode.BIND_FAILED)
		return false
	_game_port = transport.bound_port()
	var game_transport: Transport = transport
	if config.transport == ServerConfig.TransportKind.SDR and not config.offline:
		if not _start_steam_server():
			return false
		var both: Array[Transport] = [transport, sdr]
		game_transport = MultiTransport.new(both)
	var slots: int = Tuning.i(&"modes.friends_lobby_max") if Tuning.current.has_key(&"modes.friends_lobby_max") else 5
	net = ServerNet.new(game_transport, slots)
	net.flavour = config.build.flavour
	net.qa_token = "" if config.build.is_release() else config.qa_token
	var mine: Mine = null
	if not config.map_name.is_empty():
		mine = Mine.new()
		var started: int = TickTimer.now_usec()
		var cells: int = FixedMapLoader.load_cells(mine, config.map_name)
		if cells < 0:
			Log.error("the map %s did not load" % config.map_name)
			get_tree().quit(ExitCode.FATAL)
			return false
		Log.info("map %s: %d cells in %.1f ms" % [config.map_name, cells, (TickTimer.now_usec() - started) / 1000.0])
	var layouts: LbLayouts = null
	if config.generated and config.map_name.is_empty():
		mine = Mine.new()
		layouts = MineLayouts.for_run(run.header.run_seed, "", config.template_pack)
		if layouts == null:
			Log.error("the generated mine has no template pack")
			get_tree().quit(ExitCode.FATAL)
			return false
	ServerSystems.install(run, net, mine)
	if layouts != null:
		# GEN-08: the plan from the seed and the list (or the save's), before any cell is derived.
		var saved: PackedByteArray = PackedByteArray()
		var raw: Variant = Variants.dict(_resume.get("head", {})).get("plan", null)
		if raw is PackedByteArray:
			saved = raw
		if RunPlan.fix(layouts, run, saved).is_empty():
			Log.error("the run's plan failed")
			get_tree().quit(ExitCode.FATAL)
			return false
		var started_gen: int = TickTimer.now_usec()
		# A fleet server, or one on a player's machine (hosted: a private host or Night Shift;
		# Steam sets SteamDeck=1 on a Deck), whose workers yield to the game's frame.
		var workers: int = Tuning.i(&"mine.generation_workers_fleet")
		if OS.get_environment("SteamDeck") == "1":
			workers = Tuning.i(&"mine.generation_workers_deck")
		elif hosted:
			workers = Tuning.i(&"mine.generation_workers_host")
		generation = Generation.new(mine, layouts, run.header.run_seed, false, workers, hosted)
		run.add_system(generation)
		generation.start()
		Log.info("generated mine: set %s, %d cells round base camp in %.1f ms, %d workers" % [layouts.set_version(),
			mine.native.loaded_cells().size(), (TickTimer.now_usec() - started_gen) / 1000.0, workers])
	# DIR-*: the Director paces the creatures of every generated run, and of a fixed map if asked.
	if config.generated or config.director:
		Director.install(run)
	if run.saves != null:
		run.saves.save_dir = config.save_dir
	var resuming: bool = not _resume.is_empty()
	var placed: Dictionary = {}
	if mine != null:
		placed = FixedMapLoader.populate(run, config.map_name, true, not resuming, not resuming)
	if resuming:
		var restored: Dictionary = SaveResume.apply(run, net, _resume)
		Log.info("resumed run %s at tick %d (save %d), %d journaled falls and deaths applied" % [run.header.run_uuid,
			run.tick, run.saves.seq if run.saves != null else 0, int(Variants.number(restored["journal_applied"]))])
	if mine != null:
		# QA-01's minimal M1 arrival: a welcomed player's miner on base camp's cage deck (MOD-04 replaces it).
		arrival = M1Arrival.new(run, mine)
		arrival.adopt(net.seats)
		net.welcomed.connect(arrival.on_welcomed)
		Log.info("map %s placed: %d coat heaps, %d creatures, %d items, %d hooks" % [config.map_name,
			Variants.array(placed["heaps"]).size(), Variants.dict(placed["creatures"]).size(), Variants.array(placed["items"]).size(),
			int(Variants.number(placed["hooks"]))])
	_start_console()
	if not config.record_inputs_path.is_empty():
		run.inputs.recorder = InputLog.begin(run, "", config.record_inputs_path, config.tuning_profile)
		Log.info("recording applied inputs to %s" % config.record_inputs_path)
	if not config.stream_audit_path.is_empty() and not config.build.is_release() and ResourceLoader.exists(STREAM_AUDIT):
		var audit_script: GDScript = load(STREAM_AUDIT)
		_audit = audit_script.new()
		_audit.call(&"attach", run, net)
		Log.info("stream audit on; report to %s" % config.stream_audit_path)
	Log.info("listening on %s:%d (ENet, %d slots)" % [bind_address, transport.bound_port(), slots])
	if not config.build.is_release() and not hosted:
		_start_rendezvous(bind_address, transport.bound_port())
	if hosted and not _start_host_link():
		return false
	if steam_server == null:
		_print_ready(0)
	return true


## STM-04's Path A: GodotSteam Server, loaded at run time from beside the executable (an exported
## server; an editor or source run already holds GodotSteam, and the two cannot share a process),
## logged on anonymously; SDR listens once Steam says so.
func _start_steam_server() -> bool:
	var path: String = OS.get_executable_path().get_base_dir().path_join("steam_server/godotsteam_server.gdextension")
	if not SteamServerApi.load_extension(path):
		Log.error("Path A needs GodotSteam Server beside an exported server (%s); use the host relay (--host-relay)" % path)
		get_tree().quit(ExitCode.STEAM_INIT_FAILED)
		return false
	steam_server = SteamServerApi.new()
	var r: Dictionary = steam_server.init(Variants.whole(ProjectSettings.get_setting_with_override("lampblack/steam/app_id")))
	if Variants.whole(r["status"]) != SteamServerApi.Init.OK:
		Log.error("the game-server API did not start: %s" % str(r["verbal"]))
		get_tree().quit(ExitCode.STEAM_INIT_FAILED)
		return false
	sdr = SdrTransport.new(steam_server)
	steam_server.logged_on.connect(_on_steam_logged_on)
	Log.info("game server: logging on anonymously")
	return true


func _on_steam_logged_on(ok: bool, detail: String) -> void:
	if not ok:
		Log.error("game server: %s" % detail)
		_finish(ExitCode.STEAM_INIT_FAILED, "steam logon failed")
		return
	steam_server.sns_warm_up()
	var vport: int = Tuning.i(&"net.sdr_virtual_port")
	if sdr.listen("", vport) != OK:
		Log.error("game server: no SDR listen socket")
		_finish(ExitCode.BIND_FAILED, "no sdr listen socket")
		return
	if host_link != null:
		sdr.admission = host_link.admits
	Log.info("game server %d listening on SDR (virtual port %d)" % [steam_server.steam_id(), vport])
	_print_ready(steam_server.steam_id())


func _start_host_link() -> bool:
	host_link = HostLink.new()
	if host_link.start(config.control_port, config.parent_pid, config.build) != OK:
		Log.error("could not open the host link on loopback")
		get_tree().quit(ExitCode.BIND_FAILED)
		return false
	net.relay_token = host_link.token  # Path B: the host's relay tags friends with it
	host_link.status_of = func() -> Dictionary:
		return {"clients": net.sessions.welcomed().size(), "identity": str(steam_server.steam_id() if steam_server != null else 0),
			"logged_on": steam_server != null and steam_server.is_logged_on()}
	host_link.shutdown_requested.connect(func() -> void: _finish(ExitCode.OK, "the host quit"))
	host_link.parent_gone.connect(func() -> void:
		Log.info("the host's client is gone; play goes on for whoever is connected (NET-11)"))
	Log.info("host link on 127.0.0.1:%d (parent %d)" % [host_link.control_port, config.parent_pid])
	return true


## One line on stdout for the spawner (HostLinkWire.ready_line).
func _print_ready(identity: int) -> void:
	if _ready_printed or host_link == null:
		return
	_ready_printed = true
	print(HostLinkWire.ready_line(host_link.control_port, host_link.token, _game_port, identity, Tuning.i(&"net.sdr_virtual_port")))


## STM-04: a hosted server whose last client left goes after net.empty_server_linger_s.
func _linger() -> void:
	if net == null or _finishing:
		return
	var clients: int = net.sessions.welcomed().size()
	if clients > 0:
		_had_client = true
		_empty_since_usec = -1
		return
	if not _had_client:
		return
	var now: int = TickTimer.now_usec()
	if _empty_since_usec < 0:
		_empty_since_usec = now
	elif now - _empty_since_usec >= roundi(Tuning.f(&"net.empty_server_linger_s") * 1000000.0):
		_finish(ExitCode.OK, "the last client left %.0f s ago" % Tuning.f(&"net.empty_server_linger_s"))


## A clean end: the snapshot (NET-09), the host told, connections closed, Steam logged off.
func _finish(code: int, why: String) -> void:
	if _finishing:
		return
	_finishing = true
	Log.info("server ending: %s" % why)
	# The records (final state hash) first, then NET-09's last save while members are still connected.
	_finish_records()
	if run != null and run.saves != null:
		run.saves.end_abnormally(run, why)
		if net != null:
			net.service()
	if host_link != null:
		host_link.say_bye(why)
		for _i: int in 10:  # 100 ms for the bye to reach the host before the link goes
			OS.delay_msec(10)
			host_link.poll()
		host_link.close()
	if net != null:
		net.transport.close()
	if steam_server != null:
		steam_server.shutdown()
	Log.close()
	get_tree().quit(code)


## STM-02: dev-mode lobbies (the client's fake lobby backend meets here) beside the game port, on dev, QA and
## kill-test servers only. A port already taken (another server beside this one) is no failure.
func _start_rendezvous(bind_address: String, game_port: int) -> void:
	var t: EnetTransport = EnetTransport.new()
	t.build = config.build
	var port: int = LobbyRendezvousWire.port_for(game_port)
	if t.listen(bind_address, port) != OK:
		Log.warn("lobby rendezvous: port %d is taken; dev lobbies are off on this server" % port)
		return
	rendezvous = LobbyRendezvous.new(t)
	Log.info("lobby rendezvous on %s:%d" % [bind_address, port])


## FND-08: the server console on stdin, when stdin is a terminal and the debug channel exists.
func _start_console() -> void:
	if run.debug == null or OS.get_stdin_type() != OS.STD_HANDLE_CONSOLE:
		return
	_console_thread = Thread.new()
	_console_thread.start(_read_console)
	Log.info("debug console on stdin (type 'help')")


func _read_console() -> void:
	while true:
		var raw: String = OS.read_string_from_stdin(1024)
		if raw.is_empty():
			return  # end of input
		var line: String = raw.strip_edges()
		if not line.is_empty():
			run.debug.call(&"queue_console_line", line)


func _log_stats() -> void:
	var elapsed: float = (TickTimer.now_usec() - _started_usec) / 1000000.0
	var tick_times: Dictionary = run.timer.summary(TickTimer.TICK)
	var visibility: int = run.timer.percentile(TickTimer.stage_key(StageTable.Stage.VISIBILITY), 99.0)
	var road_graph: int = run.timer.percentile(TickTimer.stage_key(StageTable.Stage.ROAD_GRAPH), 99.0)
	Log.info("tick stats: %d ticks in %.3f s = %.4f Hz; overruns %d; tick p50 %d us, p99 %d us; visibility p99 %d us; road graph p99 %d us" % [
		run.tick, elapsed, run.tick / maxf(elapsed, 0.000001), loop.overruns,
		tick_times["p50"], tick_times["p99"], visibility, road_graph])
	var inputs: String = run.inputs.summary() if run.inputs != null else ""
	if not inputs.is_empty():
		Log.info("inputs: " + inputs)


## FND-09: closes the input log with the final state hash, and writes the stats file.
func _finish_records() -> void:
	var final_hash: String = run.state_hash()
	Log.info("final state hash %s after %d ticks" % [final_hash, run.tick])
	if run.inputs != null and run.inputs.recorder != null:
		run.inputs.recorder.finish(run.tick, final_hash)
	if _audit != null:
		var report: Dictionary = _audit.call(&"report")
		Log.info("stream audit: %d violations" % int(Variants.number(report["violations"])))
		var audit_file: FileAccess = FileAccess.open(config.stream_audit_path, FileAccess.WRITE)
		if audit_file != null:
			audit_file.store_string(JSON.stringify(report, "\t"))
			audit_file.close()
	if config.stats_path.is_empty():
		return
	var stages: Dictionary = {}
	for stage: int in range(1, StageTable.STAGE_COUNT + 1):
		var key: String = TickTimer.stage_key(stage)
		var summary: Dictionary = run.timer.summary(key)
		stages[StageTable.stage_name(stage)] = {"p50": summary["p50"], "p99": summary["p99"], "max": run.timer.max_usec(key)}
	var tick_summary: Dictionary = run.timer.summary(TickTimer.TICK)
	var elapsed: float = (TickTimer.now_usec() - _started_usec) / 1000000.0
	var stats: Dictionary = {
		"ticks": run.tick,
		"elapsed_s": elapsed,
		"overruns": loop.overruns,
		"tick_usec": {"p50": tick_summary["p50"], "p99": tick_summary["p99"], "max": run.timer.max_usec(TickTimer.TICK)},
		"stages_usec": stages,
		"inputs": run.inputs.counters() if run.inputs != null else {},
		"input_log": config.record_inputs_path,
		"final_state_hash": final_hash,
	}
	if generation != null:
		stats["generation"] = generation.stats()
	var file: FileAccess = FileAccess.open(config.stats_path, FileAccess.WRITE)
	if file == null:
		Log.error("could not write stats to %s" % config.stats_path)
		return
	file.store_string(JSON.stringify(stats, "\t"))
	file.close()


## NET-09: a fresh run's UUID (version 4, from the OS's cryptographic source); saves live under it.
static func _new_run_uuid() -> String:
	var b: PackedByteArray = Crypto.new().generate_random_bytes(16)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	var h: String = b.hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]


## A fixed seed (dev and QA) or a fresh one. MOD-03 owns run creation; until then the server
## draws 64 bits from the OS's cryptographic source. The seed never leaves the server.
func _run_seed() -> int:
	if config.has_seed:
		return config.run_seed
	if not config.map_name.is_empty():
		return FixedMapLoader.run_seed(FixedMapLoader.manifest(config.map_name))  # GEN-03: repeatable
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(8)
	return bytes.decode_s64(0)
