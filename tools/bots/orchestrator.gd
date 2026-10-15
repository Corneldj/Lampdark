extends SceneTree
## FND-09's soak orchestrator. Run through tools/bots/run_soak.sh:
##   run_soak.sh <soak> [--servers N] [--bots M] [--minutes T] [--seed S] [--link rtt,loss]
##               [--out DIR] [--port P] [--accelerated]
## It starts N headless servers (FND-03) and M bots on each from the source tree, runs
## tools/bots/soaks/<soak>.gd, and writes DIR/report.json: tick cost by stage, bytes per client per
## lane, receive logs, run-record paths, applied-input logs, and every process's exit code. It
## exits non-zero on a crash, an unscripted disconnect or a failed verify. --accelerated runs
## the same soak and brains inside the scenario kit, with no sockets and no waiting.

const Soak = preload("res://tools/bots/soak.gd")
const STEP_USEC: int = 50000
## Ticks a server runs beyond the bots, to start first and drain after.
const SERVER_GRACE_TICKS: int = 200

var soak: Soak
var soak_name: String = ""
var out_dir: String = ""
var base_port: int = 47900
## Ports between soak servers: each dev or QA server also opens its STM-02 lobby rendezvous at its
## game port + net.dev_lobby_port_offset (1), which must never be another server's game port.
const PORT_STRIDE: int = 4
var accelerated: bool = false
var processes: Array[Dictionary] = []
var _started_usec: int = 0
var _bots_started: bool = false
var _deadline_usec: int = 0
var _next_tick_usec: int = 0
var _failed_start: bool = false
var _begun: bool = false


func _initialize() -> void:
	if not _parse(OS.get_cmdline_user_args()):
		quit(ExitCode.BAD_ARGUMENTS)


## Autoloads join the tree only after _initialize, so the soak starts on the first frame.
func _begin() -> void:
	_begun = true
	var tuning: Node = root.get_node_or_null(^"/root/Tuning")
	if tuning != null:
		tuning.call(&"load_server")
	DirAccess.make_dir_recursive_absolute(out_dir)
	print("soak %s: %d server(s) x %d bot(s), %.1f min, seed %d%s -> %s" % [soak_name, _servers(), _bots(),
		_minutes(), int(Variants.number(soak.profile["seed"])), " (accelerated)" if accelerated else "", out_dir])
	if accelerated:
		quit(_run_accelerated())
		return
	_start_servers()
	_started_usec = Time.get_ticks_usec()
	_next_tick_usec = _started_usec
	_deadline_usec = _started_usec + roundi((_minutes() * 60.0 + SERVER_GRACE_TICKS / 20.0 + 60.0) * 1000000.0)


func _process(_delta: float) -> bool:
	if not _begun:
		_begin()
		return false
	if accelerated or _failed_start:
		return false
	var now: int = Time.get_ticks_usec()
	if not _bots_started and now - _started_usec > 2000000:
		_start_bots()
		_bots_started = true
	if now >= _next_tick_usec:
		_next_tick_usec += STEP_USEC
		soak.on_tick({"elapsed_s": (now - _started_usec) / 1000000.0, "servers_running": _running("server"),
			"bots_running": _running("bot")})
	if _bots_started and _running("server") == 0 and _running("bot") == 0:
		quit(_finish())
		return true
	if now > _deadline_usec:
		for p: Dictionary in processes:
			if OS.is_process_running(int(Variants.number(p["pid"]))):
				OS.kill(int(Variants.number(p["pid"])))
				p["ended"] = "killed at the deadline (hung)"
		quit(_finish())
		return true
	OS.delay_usec(5000)
	return false


func _parse(args: PackedStringArray) -> bool:
	if args.is_empty():
		printerr("usage: run_soak.sh <soak> [--servers N] [--bots M] [--minutes T] [--seed S] [--link rtt,loss] [--out DIR] [--port P] [--accelerated]")
		return false
	soak_name = args[0]
	var path: String = "res://tools/bots/soaks/%s.gd" % soak_name
	if not ResourceLoader.exists(path):
		printerr("no soak named '%s' (%s)" % [soak_name, path])
		return false
	var script: GDScript = load(path)
	if script == null or not script.can_instantiate():
		printerr("the soak '%s' does not load (a parse error above)" % soak_name)
		return false
	soak = script.new()
	soak.setup({})
	out_dir = ProjectSettings.globalize_path("res://build/soaks/%s" % soak_name)
	var i: int = 1
	while i < args.size():
		var flag: String = args[i]
		var value: String = args[i + 1] if i + 1 < args.size() else ""
		match flag:
			"--servers":
				soak.profile["servers"] = value.to_int()
			"--bots":
				soak.profile["bots"] = value.to_int()
			"--minutes":
				soak.profile["minutes"] = value.to_float()
			"--seed":
				soak.profile["seed"] = value.to_int()
			"--link":
				soak.profile["link"] = value
			"--out":
				out_dir = value
			"--port":
				base_port = value.to_int()
			"--accelerated":
				accelerated = true
				i -= 1
			_:
				printerr("unknown option %s" % flag)
				return false
		i += 2
	return true


func _servers() -> int:
	return int(Variants.number(soak.profile["servers"]))


func _bots() -> int:
	return int(Variants.number(soak.profile["bots"]))


func _minutes() -> float:
	return float(Variants.number(soak.profile["minutes"]))


func _bot_ticks() -> int:
	return roundi(_minutes() * 1200.0)


func _brain(index: int) -> String:
	var brains: Array = Variants.array(soak.profile.get("brains", ["wander"]))
	return str(brains[index % brains.size()])


func _spawn(kind: String, name: String, args: PackedStringArray) -> void:
	var full: PackedStringArray = PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--"])
	full.append_array(args)
	full.append_array(PackedStringArray(["--log", out_dir.path_join(name + ".log")]))
	var pid: int = OS.create_process(OS.get_executable_path(), full)
	if pid <= 0:
		printerr("could not start %s" % name)
		_failed_start = true
	processes.append({"kind": kind, "name": name, "pid": pid, "ended": "", "exit_code": -1})


func _port_of(server: int) -> int:
	return base_port + server * PORT_STRIDE


func _start_servers() -> void:
	for s: int in _servers():
		var name: String = "server_%d" % s
		_spawn("server", name, PackedStringArray(["--server", "--port", str(_port_of(s)),
			"--seed", str(int(Variants.number(soak.profile["seed"])) + s),
			"--exit-after-ticks", str(_bot_ticks() + SERVER_GRACE_TICKS),
			"--record-inputs", out_dir.path_join(name + ".inputs.jsonl"),
			"--stats-out", out_dir.path_join(name + ".stats.json")]))


func _start_bots() -> void:
	var n: int = 0
	for s: int in _servers():
		for b: int in _bots():
			var name: String = "bot_%d_%d" % [s, b]
			var args: PackedStringArray = PackedStringArray(["--bot", _brain(n), "--bot-seed", str(int(Variants.number(soak.profile["seed"])) * 100 + n),
				"--connect", "127.0.0.1:%d" % _port_of(s), "--name", name,
				"--exit-after-ticks", str(_bot_ticks()), "--receive-log", out_dir.path_join(name + ".recv.log")])
			if not str(soak.profile.get("link", "")).is_empty():
				args.append_array(PackedStringArray(["--link", str(soak.profile["link"])]))
			_spawn("bot", name, args)
			n += 1


func _running(kind: String) -> int:
	var count: int = 0
	for p: Dictionary in processes:
		if p["kind"] == kind and OS.is_process_running(int(Variants.number(p["pid"]))):
			count += 1
	return count


func _finish() -> int:
	for p: Dictionary in processes:
		p["exit_code"] = OS.get_process_exit_code(int(Variants.number(p["pid"])))
		if str(p["ended"]).is_empty():
			p["ended"] = "exited"
	var report: Dictionary = _report_base()
	for s: int in _servers():
		var name: String = "server_%d" % s
		var stats: Dictionary = _read_json(out_dir.path_join(name + ".stats.json"))
		Variants.array(report["servers"]).append({"index": s, "port": _port_of(s), "stats": stats,
			"log": out_dir.path_join(name + ".log"), "input_log": out_dir.path_join(name + ".inputs.jsonl")})
		Variants.array(report["applied_input_logs"]).append(out_dir.path_join(name + ".inputs.jsonl"))
	for p: Dictionary in processes:
		if p["kind"] != "bot":
			continue
		var recv: String = out_dir.path_join(str(p["name"]) + ".recv.log")
		var stats: Dictionary = _read_json(recv + ".stats.json")
		stats["bot"] = p["name"]
		Variants.array(report["bots"]).append(stats)
		Variants.array(report["receive_logs"]).append(recv)
		Variants.dict(report["bytes_per_client"])[p["name"]] = {"in": stats.get("bytes_in", {}), "out": stats.get("bytes_out", {})}
		if int(Variants.number(p["exit_code"])) == ExitCode.UNSCRIPTED_DISCONNECT:
			Variants.array(report["unscripted_disconnects"]).append(p["name"])
	report["processes"] = processes
	return _judge(report)


func _report_base() -> Dictionary:
	return {"soak": soak_name, "profile": soak.profile, "accelerated": accelerated, "link": soak.profile.get("link", ""),
		"servers": [], "bots": [], "tick_cost_usec": {}, "bytes_per_client": {}, "receive_logs": [],
		"run_records": [], "run_records_note": "NET-08's run records arrive with NET-01's record stage",
		"applied_input_logs": [], "processes": [], "crashes": [], "unscripted_disconnects": [], "verify_errors": []}


## Aggregates tick cost, runs verify, writes report.json and returns the exit code.
func _judge(report: Dictionary) -> int:
	var cost: Dictionary = {}
	for raw: Variant in Variants.array(report["servers"]):
		var stats: Dictionary = Variants.dict(Variants.dict(raw).get("stats", {}))
		var stages: Dictionary = Variants.dict(stats.get("stages_usec", {}))
		stages["tick"] = stats.get("tick_usec", {})
		for stage: Variant in stages.keys():
			var c: Dictionary = Variants.dict(stages[stage])
			var agg: Dictionary = Variants.dict(cost.get(stage, {"p50": 0, "p99": 0, "max": 0}))
			for field: String in ["p50", "p99", "max"]:
				agg[field] = maxi(int(Variants.number(agg[field])), int(Variants.number(c.get(field, 0))))
			cost[stage] = agg
	report["tick_cost_usec"] = cost
	for raw: Variant in Variants.array(report["processes"]):
		var p: Dictionary = Variants.dict(raw)
		var code: int = int(Variants.number(p.get("exit_code", -1)))
		if code != 0 and code != ExitCode.UNSCRIPTED_DISCONNECT:
			Variants.array(report["crashes"]).append({"name": p.get("name"), "exit_code": code, "ended": p.get("ended")})
	var errors: Array[String] = soak.verify(report)
	report["verify_errors"] = errors
	var ok: bool = errors.is_empty() and Variants.array(report["crashes"]).is_empty() \
		and Variants.array(report["unscripted_disconnects"]).is_empty()
	report["passed"] = ok
	var file: FileAccess = FileAccess.open(out_dir.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	var seconds: float = (Time.get_ticks_usec() - _started_usec) / 1000000.0 if _started_usec > 0 else 0.0
	print("soak %s %s in %.1f s; report %s" % [soak_name, "PASSED" if ok else "FAILED", seconds, out_dir.path_join("report.json")])
	for e: String in errors:
		print("  - " + e)
	return 0 if ok else 1


## The same soak and brains inside the scenario kit (tools/bots/accelerated.gd, loaded now so
## its autoload-dependent types compile after the autoloads exist).
func _run_accelerated() -> int:
	_started_usec = Time.get_ticks_usec()
	var runner: GDScript = load("res://tools/bots/accelerated.gd")
	var report: Dictionary = _report_base()
	runner.call(&"run", soak.profile, _servers(), _bots(), _bot_ticks() + SERVER_GRACE_TICKS, out_dir, _brain, report, soak)
	return _judge(report)


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	return Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
