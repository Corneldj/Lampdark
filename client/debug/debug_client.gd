class_name DebugClient
extends Node
## FND-08: the client's debug side, created by ClientMain by path outside release builds. It owns the
## console, the truth view and the QA overlay tags, runs client commands, sends server commands and
## the view switches over the debug lane, and drains the connection's debug inbox each frame. Without
## the debug channel every server command is refused here and nothing is sent.

var connection: ClientConnection = null
## MinerListener (SND-04's ears), for listener_mode.
var listener: MinerListener = null
## () -> Vector2: the view's top-left in tiles (the camera's), for the truth view.
var view_origin: Callable = func() -> Vector2: return Vector2.ZERO
var console: DebugConsole = null
var truth: TruthView = null
var overlay: QaOverlayTags = null
var truth_on: bool = false
var truth_layers: PackedStringArray = PackedStringArray(DebugCommands.LAYERS)
var overlay_on: bool = false
## Answers received from the server (tests).
var replies: Array[Dictionary] = []


func _ready() -> void:
	console = DebugConsole.new()
	add_child(console)
	console.line_entered.connect(run_line)
	truth = TruthView.new()
	truth.visible = false
	add_child(truth)
	overlay = QaOverlayTags.new()
	add_child(overlay)


## One console line; the answer goes to the console's log (and is returned).
func run_line(line: String) -> String:
	var parsed: Dictionary = DebugCommands.parse(line)
	if not Variants.flag(parsed["ok"]):
		return _say(str(parsed["error"]))
	var name: String = str(parsed["command"])
	var a: Dictionary = parsed["args"]
	match name:
		"help":
			return _say(DebugCommands.help(str(a.get("topic", ""))))
		"listener_mode":
			if listener == null or not listener.set_mode(str(a["mode"])):
				return _say("not available: screen-up is compiled out of this build")
			return _say("listener faces %s" % ("north" if str(a["mode"]) == "screen_up" else "the miner's way"))
	if connection == null or not connection.has_debug():
		return _say("refused: no debug channel (a QA token, on a QA or dev server)")
	if name == "truth" or name == "overlay":
		if name == "truth":
			truth_on = Variants.flag(a["on"])
			truth_layers = a["layers"]
			truth.layers = truth_layers
			truth.visible = truth_on
			if not truth_on:
				truth.clear()
		else:
			overlay_on = Variants.flag(a["on"])
			overlay.on = overlay_on
		connection.send(Lane.Id.DEBUG, DebugMessages.encode({"truth": truth_on, "layers": truth_layers, "overlay": overlay_on}),
			Protocol.Msg.DEBUG_SUBSCRIBE)
		return _say("%s %s" % [name, "on" if Variants.flag(a["on"]) else "off"])
	connection.send(Lane.Id.DEBUG, DebugMessages.encode({"line": line}), Protocol.Msg.DEBUG_COMMAND)
	return _say("sent")


func _process(_delta: float) -> void:
	poll()


## Drains the debug inbox: answers to the log, truth snapshots to the view, tags to the overlay.
func poll() -> void:
	if connection == null:
		return
	while not connection.debug_inbox.is_empty():
		var m: Dictionary = connection.debug_inbox.pop_front()
		var payload: PackedByteArray = m["payload"]
		var data: Dictionary = DebugMessages.decode(payload)
		match int(Variants.number(m["type"])):
			Protocol.Msg.DEBUG_REPLY:
				replies.append(data)
				_say(str(data.get("text", "")))
			Protocol.Msg.DEBUG_TRUTH:
				if truth_on:
					var origin: Vector2 = view_origin.call()
					truth.show_snapshot(data, origin)
			Protocol.Msg.DEBUG_TAG:
				var own: Vector2 = connection.view.own.get("position", Vector2.ZERO) if connection.view != null else Vector2.ZERO
				overlay.on_tag(data, connection.events, own)
	if truth_on:
		var at: Vector2 = view_origin.call()
		truth.follow(at)


func _say(text: String) -> String:
	if console != null:
		console.print_line(text)
	return text
