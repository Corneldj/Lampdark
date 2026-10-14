class_name LaunchArgs
extends RefCounted
## Typed launch-argument parser (FND-03).
##
## Arguments come from two places. Everything after `--` (OS.get_cmdline_user_args()) is
## ours, and an unknown one there is warned about. Before `--` (OS.get_cmdline_args()) the
## engine's own options also appear, so only our known flags and Steam's
## `+connect_lobby <id>` are picked out there; anything else is left to the engine.
##
## A refused argument in a release build is ignored with a warning. An unknown argument
## warns. A malformed value makes the parse fail; boot then exits with ExitCode.BAD_ARGUMENTS.

enum Kind { FLAG, INT, PORT, ENUM, STRING, HOST_PORT, U64 }

const USAGE: String = ("usage: lampblack [--server] [--mode friends|public|nightshift] [--transport enet|sdr|loopback]"
	+ " [--loopback] [--port <n>] [--offline] [--parent-pid <pid>] [--control-port <n>] [--resume <path>]"
	+ " [--connect <host:port>] [--no-steam] [--name <persona>] [--sdr-fake <lag_ms,loss_pct>] [--seed <u64>] [--map <name>] [--qa-token <t>] [--bot <brain>]"
	+ " [--bot-seed <u64>] [--link <rtt_ms,loss_pct>] [--receive-log <path>] [--record-inputs <path>] [--stream-audit <path>]"
	+ " [--stats-out <path>] [--exit-after-ticks <n>] [--tuning-profile <name>] [--tuning-hot-reload]"
	+ " [--log <path>] [--log-level debug|info|warn|error]")

const STEAM_CONNECT_LOBBY: String = "+connect_lobby"

## name -> [Kind, refused in release, enum options]
const SPEC: Dictionary = {
	"--server": [Kind.FLAG, false, []],
	"--mode": [Kind.ENUM, false, ["friends", "public", "nightshift"]],
	"--transport": [Kind.ENUM, false, ["enet", "sdr", "loopback"]],
	"--loopback": [Kind.FLAG, false, []],
	"--port": [Kind.PORT, false, []],
	"--offline": [Kind.FLAG, false, []],
	"--parent-pid": [Kind.INT, false, []],
	"--control-port": [Kind.PORT, false, []],
	"--resume": [Kind.STRING, false, []],
	"--connect": [Kind.HOST_PORT, true, []],
	"--no-steam": [Kind.FLAG, true, []],
	"--name": [Kind.STRING, true, []],
	"--sdr-fake": [Kind.STRING, true, []],
	"--seed": [Kind.U64, true, []],
	"--qa-token": [Kind.STRING, true, []],
	"--bot": [Kind.STRING, true, []],
	"--bot-seed": [Kind.U64, true, []],
	"--link": [Kind.STRING, true, []],
	"--receive-log": [Kind.STRING, true, []],
	"--record-inputs": [Kind.STRING, true, []],
	"--stream-audit": [Kind.STRING, true, []],
	"--map": [Kind.STRING, false, []],
	"--stats-out": [Kind.STRING, true, []],
	"--exit-after-ticks": [Kind.INT, true, []],
	"--tuning-profile": [Kind.STRING, true, []],
	"--tuning-hot-reload": [Kind.FLAG, true, []],
	"--log": [Kind.STRING, false, []],
	"--log-level": [Kind.ENUM, false, ["debug", "info", "warn", "error"]],
}

const MODES: Dictionary = {
	"friends": ServerConfig.Mode.FRIENDS,
	"public": ServerConfig.Mode.PUBLIC,
	"nightshift": ServerConfig.Mode.NIGHTSHIFT,
}
const TRANSPORTS: Dictionary = {
	"enet": ServerConfig.TransportKind.ENET,
	"sdr": ServerConfig.TransportKind.SDR,
	"loopback": ServerConfig.TransportKind.LOOPBACK,
}

## False when a value was malformed; `error` then says which.
var ok: bool = true
var error: String = ""
var warnings: PackedStringArray = PackedStringArray()

var wants_server: bool = false
var log_path: String = ""
var log_level: String = "info"
var server: ServerConfig = ServerConfig.new()
var client: ClientConfig = ClientConfig.new()


## Parses the running process's arguments.
static func from_os(build: BuildInfo) -> LaunchArgs:
	var engine_args: PackedStringArray = OS.get_cmdline_args()
	var cut: int = engine_args.find("--")
	if cut >= 0:
		engine_args = engine_args.slice(0, cut)
	return parse(engine_args, OS.get_cmdline_user_args(), build)


static func parse(engine_args: PackedStringArray, user_args: PackedStringArray,
		build: BuildInfo) -> LaunchArgs:
	var result: LaunchArgs = LaunchArgs.new()
	result.server.build = build
	result.client.build = build
	result._scan(engine_args, build, false)
	if result.ok:
		result._scan(user_args, build, true)
	return result


func _scan(args: PackedStringArray, build: BuildInfo, strict: bool) -> void:
	var index: int = 0
	while index < args.size() and ok:
		var raw: String = args[index]
		index += 1
		var name: String = raw
		var value: String = ""
		var has_inline_value: bool = false
		if raw.begins_with("--") and raw.contains("="):
			name = raw.get_slice("=", 0)
			value = raw.substr(name.length() + 1)
			has_inline_value = true

		if name == STEAM_CONNECT_LOBBY:
			if index >= args.size():
				_fail("+connect_lobby needs a lobby id")
				return
			client.connect_lobby = args[index]
			index += 1
			continue

		if not SPEC.has(name):
			if strict:
				warnings.append("unknown argument %s ignored" % raw)
			continue

		var spec: Array = SPEC[name]
		var kind: Kind = spec[0]
		var refused: bool = spec[1]
		var options: Array = spec[2]
		if kind != Kind.FLAG and not has_inline_value:
			if index >= args.size() or (args[index].begins_with("--") and kind != Kind.STRING):
				_fail("%s needs a value" % name)
				return
			value = args[index]
			index += 1

		if refused and build.is_release():
			warnings.append("%s is not available in release builds; ignored" % name)
			continue
		_apply(name, kind, value, options)


func _apply(name: String, kind: Kind, value: String, options: Array) -> void:
	match kind:
		Kind.ENUM:
			if not value in options:
				_fail("%s must be one of %s, got '%s'" % [name, "|".join(PackedStringArray(options)), value])
				return
		Kind.INT:
			if not value.is_valid_int() or value.to_int() < 1:
				_fail("%s must be a positive integer, got '%s'" % [name, value])
				return
		Kind.PORT:
			if not value.is_valid_int() or value.to_int() < 1 or value.to_int() > 65535:
				_fail("%s must be a port from 1 to 65535, got '%s'" % [name, value])
				return
		Kind.HOST_PORT:
			var colon: int = value.rfind(":")
			var port_text: String = value.substr(colon + 1) if colon > 0 else ""
			if colon <= 0 or not port_text.is_valid_int() or port_text.to_int() < 1 or port_text.to_int() > 65535:
				_fail("%s must be host:port, got '%s'" % [name, value])
				return
		Kind.STRING:
			if value.is_empty():
				_fail("%s needs a value" % name)
				return

	match name:
		"--server":
			wants_server = true
		"--mode":
			server.mode = MODES[value]
		"--transport":
			server.transport = TRANSPORTS[value]
		"--loopback":
			server.transport = ServerConfig.TransportKind.LOOPBACK
		"--port":
			server.port = value.to_int()
		"--offline":
			server.offline = true
		"--parent-pid":
			server.parent_pid = value.to_int()
		"--control-port":
			server.control_port = value.to_int()
		"--resume":
			server.resume_path = value
		"--connect":
			client.connect_target = value
		"--no-steam":
			client.no_steam = true
		"--name":
			client.persona_name = value
		"--sdr-fake":
			var parts: PackedStringArray = value.split(",")
			if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_float():
				_fail("--sdr-fake needs lag_ms,loss_pct")
				return
			client.sdr_fake = value
		"--seed":
			var parsed: Array = parse_u64(value)
			if not parsed[0]:
				_fail("--seed must be an unsigned 64-bit decimal, got '%s'" % value)
				return
			server.has_seed = true
			server.run_seed = parsed[1]
		"--qa-token":
			server.qa_token = value
			client.qa_token = value
		"--bot":
			client.bot_script = value
		"--bot-seed":
			var bot_seed: Array = parse_u64(value)
			if not bot_seed[0]:
				_fail("--bot-seed must be an unsigned 64-bit decimal, got '%s'" % value)
				return
			client.bot_seed = bot_seed[1]
		"--link":
			var parts: PackedStringArray = value.split(",")
			if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_float() \
					or parts[0].to_int() < 0 or parts[1].to_float() < 0.0 or parts[1].to_float() > 100.0:
				_fail("--link must be rtt_ms,loss_pct (for example 120,2), got '%s'" % value)
				return
			client.link_rtt_ms = parts[0].to_int()
			client.link_loss_pct = parts[1].to_float()
		"--receive-log":
			client.receive_log_path = value
		"--record-inputs":
			server.record_inputs_path = value
		"--stream-audit":
			server.stream_audit_path = value
		"--map":
			server.map_name = value
		"--stats-out":
			server.stats_path = value
		"--exit-after-ticks":
			server.exit_after_ticks = value.to_int()
			client.exit_after_ticks = value.to_int()
		"--tuning-profile":
			server.tuning_profile = value
		"--tuning-hot-reload":
			server.tuning_hot_reload = true
		"--log":
			log_path = value
		"--log-level":
			log_level = value


func _fail(message: String) -> void:
	ok = false
	error = message


## Parses an unsigned 64-bit decimal into an int holding the same 64 bits.
## Returns [ok: bool, value: int].
static func parse_u64(text: String) -> Array:
	if text.is_empty() or text.length() > 20:
		return [false, 0]
	var high: int = 0
	var low: int = 0
	for character: String in text:
		if character < "0" or character > "9":
			return [false, 0]
		low = low * 10 + character.to_int()
		high = high * 10 + (low >> 32)
		low &= 0xFFFFFFFF
		if high > 0xFFFFFFFF:
			return [false, 0]
	return [true, (high << 32) | low]


## Formats an int's 64 bits as an unsigned decimal (the inverse of parse_u64).
static func u64_to_string(value: int) -> String:
	if value >= 0:
		return str(value)
	# Split off the top bit's worth: value = 2^63 + rest, so print (2^63 + rest) by halves.
	var high: int = (value >> 32) & 0xFFFFFFFF
	var low: int = value & 0xFFFFFFFF
	var digits: PackedStringArray = PackedStringArray()
	while high != 0 or low != 0:
		var remainder_high: int = high % 10
		high = high / 10
		var combined: int = (remainder_high << 32) | low
		low = combined / 10
		digits.append(str(combined % 10))
	digits.reverse()
	return "".join(digits)
