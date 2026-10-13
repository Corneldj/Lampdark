extends RefCounted
## FND-09's headless bot client: `--bot <brain> --connect <host:port> --bot-seed <n>
## [--link rtt_ms,loss_pct] [--receive-log <path>]` (dev and QA, from the source tree). It uses
## the real client networking, sends exactly one input per client tick from its brain, and logs
## every received message with its receive time. No rendering, no audio device, no Steam.
##
## At exit it writes <receive log>.stats.json: inputs sent, frames and bytes per lane in and
## out, the link settings, and how the connection ended.

const Brain = preload("res://tools/bots/brain.gd")
const BotContext = preload("res://tools/bots/bot_context.gd")
const TICK_USEC: int = 50000

var config: ClientConfig
var connection: ClientConnection
var brain: RefCounted
var ticks: int = 0
var exit_code: int = -1
var _next_tick_usec: int = 0
var _received: Array[Dictionary] = []
var _log: FileAccess = null
var _started_usec: int = 0


## The bot's transport: ENet, behind NET-12's link filter when --link is given.
static func make_transport(bot_config: ClientConfig) -> Transport:
	var enet: EnetTransport = EnetTransport.new()
	if bot_config.link_rtt_ms < 0:
		return enet
	return LinkEmulator.new(enet, bot_config.link_rtt_ms, bot_config.link_loss_pct, bot_config.bot_seed | 1)


func start(bot_config: ClientConfig) -> bool:
	config = bot_config
	brain = Brain.create(config.bot_script, config.bot_seed)
	if brain == null:
		return false
	var target: String = config.connect_target
	if target.is_empty():
		Log.error("a bot needs --connect <host:port>")
		return false
	connection = ClientConnection.new(make_transport(config))
	connection.identity = config.persona_name if not config.persona_name.is_empty() else "bot-%s" % LaunchArgs.u64_to_string(config.bot_seed)
	connection.seat_request = Protocol.Seat.BOT
	connection.message_observer = _on_message
	if not config.receive_log_path.is_empty():
		_log = FileAccess.open(config.receive_log_path, FileAccess.WRITE)
		if _log == null:
			Log.error("cannot write the receive log %s" % config.receive_log_path)
			return false
		_log.store_line("# usec\tlane\ttype\tbytes")
	var host: String = target.substr(0, target.rfind(":"))
	var port: int = target.substr(target.rfind(":") + 1).to_int()
	if not connection.start(host, port):
		Log.error("bot could not start a connection to %s" % target)
		return false
	_started_usec = Time.get_ticks_usec()
	_next_tick_usec = _started_usec + TICK_USEC
	var notes: PackedStringArray = brain.get(&"notes")
	Log.info("bot %s (%s, seed %s) connecting to %s%s" % [connection.identity, config.bot_script,
		LaunchArgs.u64_to_string(config.bot_seed), target,
		", link %d ms / %.1f%%" % [config.link_rtt_ms, config.link_loss_pct] if config.link_rtt_ms >= 0 else ""])
	for note: String in notes:
		Log.warn("bot brain: " + note)
	return true


## Called every frame. Returns -1 while running, then the exit code.
func process() -> int:
	connection.poll()
	if connection.state == ClientConnection.State.DROPPED or connection.state == ClientConnection.State.REJECTED:
		Log.error("bot lost its connection before its script ended (%s)" % connection.drop_reason)
		return _finish(ExitCode.UNSCRIPTED_DISCONNECT, "unscripted disconnect: " + connection.drop_reason)
	var now: int = Time.get_ticks_usec()
	while now >= _next_tick_usec:
		_next_tick_usec += TICK_USEC
		ticks += 1
		if connection.state == ClientConnection.State.CONNECTED:
			_tick()
		if config.exit_after_ticks > 0 and ticks >= config.exit_after_ticks:
			connection.close()
			return _finish(ExitCode.OK, "script ended")
	return -1


func _tick() -> void:
	var ctx: BotContext = BotContext.new()
	ctx.tick = ticks
	ctx.frame_tick = connection.last_frame_tick
	ctx.received = _received
	_received = []
	var record: InputRecord = brain.call(&"think", ctx)
	for action: Array in ctx.actions:
		connection.inputs.queue_action(int(Variants.number(action[0])) as ActionRecord.Kind,
			int(Variants.number(action[1])), ticks, int(Variants.number(action[2])))
	for voice: Array in ctx.voice:
		var payload: PackedByteArray = PackedByteArray()
		payload.resize(1 + int(Variants.number(voice[1])))
		payload[0] = int(Variants.number(voice[0]))
		connection.send(Lane.Id.VOICE, payload, Protocol.Msg.VOICE)
	var stamp: PackedInt64Array = connection.stamp_for_send(Transport.now_usec())
	connection.inputs.send_tick(connection, record, stamp[0], stamp[1])


func _on_message(lane: int, data: PackedByteArray, now_usec: int) -> void:
	var message: Dictionary = Protocol.unframe(data)
	var type: int = int(Variants.number(message.get("type", -1))) if not message.is_empty() else -1
	_received.append({"lane": lane, "type": type, "bytes": data})
	if _log != null:
		_log.store_line("%d\t%d\t%d\t%d" % [now_usec, lane, type, data.size()])


func _finish(code: int, how: String) -> int:
	exit_code = code
	if _log != null:
		_log.close()
		_log = null
	if not config.receive_log_path.is_empty():
		var notes: PackedStringArray = brain.get(&"notes")
		var stats: Dictionary = {
			"bot": connection.identity, "brain": config.bot_script, "seed": LaunchArgs.u64_to_string(config.bot_seed),
			"ticks": ticks, "inputs_sent": connection.inputs.packets_sent, "frames_received": connection.frames_received,
			"bytes_in": _by_lane_name(connection.bytes_in), "bytes_out": _by_lane_name(connection.bytes_out),
			"seconds": (Time.get_ticks_usec() - _started_usec) / 1000000.0,
			"link": {"rtt_ms": config.link_rtt_ms, "loss_pct": config.link_loss_pct, "filter": connection.transport is LinkFilter},
			"ended": how, "exit_code": code, "notes": Array(notes),
			"receive_log": config.receive_log_path,
		}
		var file: FileAccess = FileAccess.open(config.receive_log_path + ".stats.json", FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(stats, "\t"))
			file.close()
	Log.info("bot %s: %s after %d ticks, %d inputs sent, %d frames received" % [connection.identity, how, ticks,
		connection.inputs.packets_sent, connection.frames_received])
	return code


static func _by_lane_name(by_lane: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for lane: Variant in by_lane.keys():
		out[Lane.lane_name(int(Variants.number(lane)))] = by_lane[lane]
	return out
