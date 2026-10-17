class_name LocalServerHost
extends Node
## STM-04 (GDD §15.1, §15.10): a private host's client runs the headless server as a separate process
## and connects to it like any client, so even the host gets a filtered stream. It spawns the server
## (an export's lampblack_server beside the client; a source run's own engine with --server), reads
## its ready line, opens the token-authenticated control link, sends the lobby's members, and at Go
## down the run options (MOD-03: the run is created then, from the crew seated), watches the process
## every frame, shuts it down cleanly, and never leaves an orphan.
## A restarted client reattaches through user://local_server.lock.
##
## Paths: A, the server logs on to Steam as an anonymous game server and listens on SDR itself
## (exports: it loads GodotSteam Server at run time); B (--host-relay, and every source run), the
## host's client holds SDR and relays each friend over loopback (HostRelay). Night Shift spawns
## offline: loopback only, no Steam at all.

enum State { OFF, STARTING, READY, STOPPING, ENDED }
enum Path { A, B, OFFLINE }

const LOCK_PATH: String = "user://local_server.lock"
const STOP_WAIT_S: float = 5.0

## The ready line's fields: {control, token, game, identity, vport} (ints but token).
signal server_ready(info: Dictionary)
## The process ended; `crashed` unless the host asked it to stop.
signal ended(code: int, crashed: bool)
signal link_status(status: Dictionary)
## MOD-03: the run began at the host's start, or the start was refused (the server's plain words).
signal run_started
signal start_refused(reason: String)
## MOD-05: whether the crew may knock off now (UI-05's "Knock off" shows only then), and a refusal.
signal knock_off_available(on: bool)
signal knock_off_refused(reason: String)

var state: State = State.OFF
var path: Path = Path.A
var pid: int = 0
var info: Dictionary = {}
var log_path: String = ""
var link: EnetTransport = null
var _link_peer: int = -1
var _link_up: bool = false
var _io: FileAccess = null
## Held (and drained) for the process's life: a pipe whose reading end closes kills a writer (SIGPIPE).
var _err: FileAccess = null
## A clean end always says bye on the link first (Godot reports a killed process's code as 0).
var _bye: bool = false
## Spawned here (Godot can wait on it) or reattached (another process's child: watched by PID).
var _child: bool = false
var _pending: String = ""
var _started_usec: int = 0
var _stop_asked_usec: int = -1
var _queued: Array[Dictionary] = []
## Tests: more launch arguments (a tuning profile), and an executable in place of this build's.
var extra_args: PackedStringArray = PackedStringArray()
var executable_override: String = ""


func _init() -> void:
	name = "LocalServerHost"
	process_mode = Node.PROCESS_MODE_ALWAYS


## The executable and arguments for this build: {path, args}.
static func command(which: Path, log_file: String, resume_path: String = "") -> Dictionary:
	# MOD-03: a hosted run is a generated mine, created at the host's start.
	var args: PackedStringArray = PackedStringArray(["--server", "--parent-pid", str(OS.get_process_id()), "--log", log_file, "--generate"])
	match which:
		Path.A:
			args.append_array(["--mode", "friends", "--transport", "sdr"])
		Path.B:
			args.append_array(["--mode", "friends", "--loopback"])
		Path.OFFLINE:
			args.append_array(["--mode", "nightshift", "--offline", "--loopback"])
	if not resume_path.is_empty():
		args.append_array(["--resume", resume_path])
	if OS.has_feature("template"):
		var dir: String = OS.get_executable_path().get_base_dir()
		var exe: String = "lampblack_server.exe" if OS.get_name() == "Windows" else "lampblack_server.x86_64"
		return {"path": dir.path_join(exe), "args": args}
	# A source run: this engine, the project, headless.
	var engine: PackedStringArray = PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--"])
	engine.append_array(args)
	return {"path": OS.get_executable_path(), "args": engine}


## Path A needs GodotSteam Server beside an exported server; a source run takes Path B.
static func default_path(force_relay: bool) -> Path:
	return Path.B if force_relay or not OS.has_feature("template") else Path.A


func start(which: Path, resume_path: String = "") -> bool:
	if state == State.STARTING or state == State.READY:
		return false
	path = which
	log_path = ProjectSettings.globalize_path("user://logs/server.log")
	DirAccess.make_dir_recursive_absolute(log_path.get_base_dir())
	var cmd: Dictionary = command(which, log_path, resume_path)
	if not executable_override.is_empty():
		var plain: PackedStringArray = cmd["args"]
		var at: int = plain.find("--server")
		cmd = {"path": executable_override, "args": plain.slice(at)}
	var full: PackedStringArray = cmd["args"]
	full.append_array(extra_args)
	cmd["args"] = full
	if not FileAccess.file_exists(str(cmd["path"])):
		Log.error("local server: no %s" % cmd["path"])
		return false
	var args: PackedStringArray = cmd["args"]
	var spawned: Dictionary = OS.execute_with_pipe(str(cmd["path"]), args, false)
	if spawned.is_empty():
		Log.error("local server: the spawn failed")
		return false
	pid = Variants.whole(spawned["pid"])
	_io = spawned["stdio"]
	_err = spawned["stderr"]
	_pending = ""
	_bye = false
	_child = true
	_started_usec = Time.get_ticks_usec()
	state = State.STARTING
	Log.info("local server: spawned pid %d (path %s)" % [pid, Path.keys()[which]])
	return true


func _process(_delta: float) -> void:
	match state:
		State.STARTING:
			_read_ready()
			if state == State.STARTING and Time.get_ticks_usec() - _started_usec > roundi(Tuning.f(&"net.local_server_ready_timeout_s") * 1000000.0):
				Log.error("local server: no ready line within %.0f s" % Tuning.f(&"net.local_server_ready_timeout_s"))
				OS.kill(pid)  # Godot collects the child as it kills it
				_end(-1, true)
				return
		State.READY, State.STOPPING:
			_poll_link()
	_drain()
	if state != State.OFF and state != State.ENDED and pid > 0 and _child:
		# One call that both checks and collects the child (two would collect it twice).
		var code: int = OS.get_process_exit_code(pid)
		if code != -1:
			_poll_link()  # a bye may be waiting
			_end(code, code != 0 or (not _bye and state != State.STOPPING))
		elif not Variants.flag(ClassDB.class_call_static(&"LbCoreInfo", &"process_alive", pid)):
			# Windows forgets a killed child at once (no exit code ever comes): the OS says it is gone.
			_poll_link()
			_end(-1, not _bye and state != State.STOPPING)
	elif state != State.OFF and state != State.ENDED and pid > 0 and not _child:
		if not Variants.flag(ClassDB.class_call_static(&"LbCoreInfo", &"process_alive", pid)):
			_poll_link()
			_end(0, not _bye and state != State.STOPPING)
	if state == State.STOPPING and _stop_asked_usec > 0 and Time.get_ticks_usec() - _stop_asked_usec > roundi(STOP_WAIT_S * 1000000.0):
		_stop_asked_usec = -1
		Log.warn("local server: still running %.0f s after shutdown; killing it" % STOP_WAIT_S)
		OS.kill(pid)  # Godot collects the child as it kills it
		_end(-1, false)


## Reads and drops whatever the server wrote after its ready line (it logs to its own file).
func _drain() -> void:
	if _io != null and state != State.STARTING:
		_io.get_buffer(65536)
	if _err != null:
		_err.get_buffer(65536)


func _read_ready() -> void:
	if _io == null:
		return
	var chunk: PackedByteArray = _io.get_buffer(4096)
	if chunk.is_empty():
		return
	_pending += chunk.get_string_from_utf8()
	while _pending.contains("\n"):
		var line: String = _pending.substr(0, _pending.find("\n"))
		_pending = _pending.substr(_pending.find("\n") + 1)
		var fields: Dictionary = HostLinkWire.parse_ready(line)
		if not fields.is_empty():
			_on_ready(fields)
			return


func _on_ready(fields: Dictionary) -> void:
	info = {"control": str(fields["control"]).to_int(), "token": str(fields["token"]), "game": str(fields["game"]).to_int(),
		"identity": str(fields["identity"]).to_int(), "vport": str(fields["vport"]).to_int()}
	_open_link()
	_write_lock()
	state = State.READY
	Log.info("local server: ready in %.2f s (game port %d, identity %d)" % [(Time.get_ticks_usec() - _started_usec) / 1000000.0,
		Variants.whole(info["game"]), Variants.whole(info["identity"])])
	server_ready.emit(info)


func _open_link() -> void:
	link = EnetTransport.new()
	link.connection_timeout_usec = 0
	_link_up = false
	_link_peer = link.connect_to("127.0.0.1", Variants.whole(info["control"]))


func _poll_link() -> void:
	if link == null:
		return
	for ev: TransportEvent in link.poll():
		match ev.kind:
			TransportEvent.Kind.CONNECTED:
				_link_up = true
				_send({"t": "auth", "token": str(info["token"])})
				for m: Dictionary in _queued:
					_send(m)
				_queued.clear()
			TransportEvent.Kind.MESSAGE:
				var m: Dictionary = HostLinkWire.decode(ev.data)
				match str(m.get("t", "")):
					"status":
						link_status.emit(m)
					"bye":
						_bye = true
					"started":
						run_started.emit()
					"start_refused":
						start_refused.emit(str(m.get("reason", "")))
					"knock_off_available":
						knock_off_available.emit(Variants.flag(m.get("on", false)))
					"knock_off_refused":
						knock_off_refused.emit(str(m.get("reason", "")))
			TransportEvent.Kind.DROPPED:
				_link_up = false
	link.flush()


func _send(m: Dictionary) -> void:
	if _link_up:
		link.send(_link_peer, Lane.Id.CONTROL, HostLinkWire.encode(m))
	else:
		_queued.append(m)


## The lobby's members, for STM-02's admission rule on the server.
func send_members(owner: int, ids: PackedInt64Array, code_users: PackedInt64Array, vouched: PackedInt64Array) -> void:
	_send({"t": "members", "owner": str(owner), "ids": HostLinkWire.ids_to_strings(ids),
		"code_users": HostLinkWire.ids_to_strings(code_users), "vouched": HostLinkWire.ids_to_strings(vouched)})


func send_options(options: Dictionary) -> void:
	_send({"t": "options", "options": options})


## MOD-03: Go down: the server creates the run from these options (RunOptions.to_dict()) and the
## crew seated now. `unlocked`: the host has unlocked the hard variants (MOD-01).
func send_start(options: Dictionary, unlocked: bool) -> void:
	_send({"t": "start", "options": options, "unlocked": unlocked})


## MOD-05: "Knock off": the server saves the run and ends the session if the crew may knock off.
func send_knock_off() -> void:
	_send({"t": "knock_off"})


## A clean stop: the server snapshots, says bye and exits 0; killed if it lingers.
func stop() -> void:
	if state != State.READY and state != State.STARTING:
		return
	_send({"t": "shutdown"})
	if link != null:
		link.flush()
	state = State.STOPPING
	_stop_asked_usec = Time.get_ticks_usec()


func _end(code: int, crashed: bool) -> void:
	state = State.ENDED
	if link != null:
		link.close()
		link = null
	_clear_lock()
	Log.info("local server: ended with code %d%s; log %s" % [code, " (crashed)" if crashed else "", log_path])
	ended.emit(code, crashed)


func _write_lock() -> void:
	var f: FileAccess = FileAccess.open(LOCK_PATH, FileAccess.WRITE)
	if f != null:
		var lock: Dictionary = info.duplicate()
		lock["pid"] = pid
		lock["identity"] = str(info["identity"])
		lock["path"] = Path.keys()[path]
		f.store_string(JSON.stringify(lock))
		f.close()


func _clear_lock() -> void:
	if FileAccess.file_exists(LOCK_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LOCK_PATH))


## A restarted client: a server from the lock that is still running is taken up again.
func reattach() -> bool:
	if not FileAccess.file_exists(LOCK_PATH):
		return false
	var lock: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(LOCK_PATH)))
	var old: int = Variants.whole(lock.get("pid", 0))
	if old <= 0 or not Variants.flag(ClassDB.class_call_static(&"LbCoreInfo", &"process_alive", old)):
		_clear_lock()
		return false
	pid = old
	_child = false
	path = Path.A if str(lock.get("path", "A")) == "A" else Path.B
	info = {"control": Variants.whole(lock.get("control", 0)), "token": str(lock.get("token", "")), "game": Variants.whole(lock.get("game", 0)),
		"identity": str(lock.get("identity", "0")).to_int(), "vport": Variants.whole(lock.get("vport", 0))}
	_open_link()
	state = State.READY
	Log.info("local server: reattached to pid %d" % pid)
	server_ready.emit(info)
	return true


## Lets go of a running server without stopping it, as a crashed client would (tests, and a
## client that hands its server to a restart).
func forget() -> void:
	if link != null:
		link.close()
		link = null
	state = State.OFF
	pid = 0


func _exit_tree() -> void:
	# Never an orphan: a client leaving the tree with its server up asks it to stop.
	if state == State.READY or state == State.STARTING:
		stop()
		_poll_link()
