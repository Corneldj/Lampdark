extends Node
## The headless server entry (FND-03). It loads tuning (FND-05), builds the RunState and
## drives NET-01's SimLoop from the monotonic clock, sleeping to each 50 ms deadline.
## The transport (NET-02) registers into stage 1 when it exists.

## Log tick-rate statistics this often, in ticks (60 s at 20 Hz).
const STATS_EVERY_TICKS: int = 1200
## NET-08: the stream audit, loaded by path in dev and QA servers only (tools/ is not in a pack).
const STREAM_AUDIT: String = "res://tools/stream_audit/stream_audit.gd"

var config: ServerConfig = null
var run: RunState = null
var loop: SimLoop = null
var net: ServerNet = null
var _started_usec: int = 0
var _last_stats_tick: int = 0
## FND-08: the server console reads stdin on its own thread (dev and QA, a terminal only).
var _console_thread: Thread = null
var _audit: RefCounted = null


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

	run = RunState.create(_run_seed(), config.mode, config.offline)
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
	loop.pump(TickTimer.now_usec())
	if run.tick - _last_stats_tick >= STATS_EVERY_TICKS:
		_last_stats_tick = run.tick
		_log_stats()
	if loop.is_done():
		Log.info("exit after %d ticks" % loop.ticks_run)
		_log_stats()
		_finish_records()
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
	if config.transport == ServerConfig.TransportKind.SDR:
		Log.error("the SDR transport arrives with STM-03")
		get_tree().quit(ExitCode.BIND_FAILED)
		return false
	var transport: EnetTransport = EnetTransport.new()
	transport.build = config.build
	var port: int = config.port if config.port > 0 else Tuning.i(&"net.dev_port")
	var bind_address: String = "127.0.0.1" if config.transport == ServerConfig.TransportKind.LOOPBACK or config.build.is_release() else "*"
	var error: Error = transport.listen(bind_address, port)
	if error != OK:
		Log.error("could not listen on %s:%d (%s)" % [bind_address, port, error_string(error)])
		get_tree().quit(ExitCode.BIND_FAILED)
		return false
	var slots: int = Tuning.i(&"modes.friends_lobby_max") if Tuning.current.has_key(&"modes.friends_lobby_max") else 5
	net = ServerNet.new(transport, slots)
	net.flavour = config.build.flavour
	net.qa_token = "" if config.build.is_release() else config.qa_token
	ServerSystems.install(run, net)
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
	return true


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
	var file: FileAccess = FileAccess.open(config.stats_path, FileAccess.WRITE)
	if file == null:
		Log.error("could not write stats to %s" % config.stats_path)
		return
	file.store_string(JSON.stringify(stats, "\t"))
	file.close()


## A fixed seed (dev and QA) or a fresh one. MOD-03 owns run creation; until then the server
## draws 64 bits from the OS's cryptographic source. The seed never leaves the server.
func _run_seed() -> int:
	if config.has_seed:
		return config.run_seed
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(8)
	return bytes.decode_s64(0)
