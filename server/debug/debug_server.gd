class_name DebugServer
extends SimSystem
## FND-08: the server end of the debug channel (dev and QA servers only; this folder is not in a
## release pack, and ServerSystems installs it only outside release). Stage RECEIVE, after the
## network: it runs console lines from debug-granted clients (the debug lane) and from the server's
## stdin console through the shared DebugCommands registry, answers each on the issuer's debug lane,
## and records each client's truth layers and overlay switch for TruthPublisher and QaOverlayTagger.
## Every command is logged with its issuer and tick; a state-changing one taints the run
## (header.debug_tainted, and a telemetry line). Commands whose system does not exist yet answer
## "not available" and change nothing. Never in the state hash.

const NOT_AVAILABLE: String = "not available"
const OPEN_SEARCH_TILES: int = 20
const KINDS: Dictionary = {"moth": WorldIds.EntityKind.MOTH, "tapper": WorldIds.EntityKind.TAPPER, "stythe": WorldIds.EntityKind.STYTHE}

var net: ServerNet = null
## slot -> {truth: bool, layers: PackedStringArray, overlay: bool}
var subscriptions: Dictionary = {}
## Lines typed at the server's console (stdin), queued by its reader thread; run with issuer -1.
var console_lines: Array[String] = []
var _console_mutex: Mutex = Mutex.new()
## {tick, issuer, line, ok, reply}, newest last (the tests and the Inquiry's taint note).
var history: Array[Dictionary] = []


func _init(server_net: ServerNet) -> void:
	net = server_net


func stage() -> int:
	return StageTable.Stage.RECEIVE


func order() -> int:
	return 50


func system_name() -> String:
	return "debug_server"


func hashed() -> bool:
	return false


## From the stdin reader thread.
func queue_console_line(line: String) -> void:
	_console_mutex.lock()
	console_lines.append(line)
	_console_mutex.unlock()


func tick(run: RunState) -> void:
	for item: Variant in Variants.array(net.routed.get(Lane.Id.DEBUG, [])):
		var m: Array = item
		var slot: int = int(Variants.number(m[0]))
		var payload: PackedByteArray = m[2]
		var data: Dictionary = DebugMessages.decode(payload)
		match int(Variants.number(m[1])):
			Protocol.Msg.DEBUG_COMMAND:
				var reply: Dictionary = execute(run, str(data.get("line", "")), slot)
				_reply(slot, reply)
			Protocol.Msg.DEBUG_SUBSCRIBE:
				subscriptions[slot] = {"truth": Variants.flag(data.get("truth", false)),
					"layers": PackedStringArray(Variants.array(data.get("layers", []))), "overlay": Variants.flag(data.get("overlay", false))}
	net.routed.erase(Lane.Id.DEBUG)
	_console_mutex.lock()
	var lines: Array[String] = console_lines.duplicate()
	console_lines.clear()
	_console_mutex.unlock()
	for line: String in lines:
		var reply: Dictionary = execute(run, line, -1)
		print("> %s\n%s" % [line, reply["text"]])


func subscription(slot: int) -> Dictionary:
	return Variants.dict(subscriptions.get(slot, {}))


## Runs one console line for `issuer` (a slot, or -1 for the server console): {ok, text}.
func execute(run: RunState, line: String, issuer: int) -> Dictionary:
	var parsed: Dictionary = DebugCommands.parse(line)
	var result: Dictionary = {"ok": false, "text": str(parsed["error"])}
	if Variants.flag(parsed["ok"]):
		result = _run_command(run, str(parsed["command"]), Variants.dict(parsed["args"]), issuer)
		if Variants.flag(parsed["clamped"]):
			result["text"] = str(result["text"]) + " (clamped to range)"
	var who: String = "server console" if issuer < 0 else "slot %d" % issuer
	Log.info("debug command '%s' by %s at tick %d: %s" % [line, who, run.tick, result["text"]])
	if Variants.flag(result["ok"]) and DebugCommands.taints(str(parsed["command"])) and not run.header.debug_tainted:
		run.header.debug_tainted = true
		Log.info("telemetry debug_tainted command=%s tick=%d" % [parsed["command"], run.tick])
	history.append({"tick": run.tick, "issuer": issuer, "line": line, "ok": result["ok"], "reply": result["text"]})
	return result


func _run_command(run: RunState, name: String, a: Dictionary, issuer: int) -> Dictionary:
	match name:
		"help":
			return _ok(DebugCommands.help(str(a.get("topic", ""))))
		"spawn":
			return _spawn(run, a, issuer)
		"teleport":
			return _teleport(run, a, issuer)
		"set_pull":
			return _set_pull(run, a, issuer)
		"set_intensity":
			return _set_intensity(run, a, issuer)
		"creatures":
			return _creatures(run, a)
		"freeze_ai":
			if run.creatures == null:
				return _no("no creature system")
			run.creatures.set_frozen(run, Variants.flag(a["on"]))
			return _ok("AI %s (creatures; Hired Hands and Bess arrive with MOD-08)" % ("frozen" if Variants.flag(a["on"]) else "running"))
		"apex":
			if run.apex == null:
				return _no("no apex (LFT-09)")
			run.apex.force(run, Variants.flag(a["on"]))
			return _ok("apex %s" % ("on: the pit wakes" if run.apex.active else "off"))
		"truth", "overlay":
			if issuer < 0:
				return _no("a client view (use the client console)")
			var sub: Dictionary = subscription(issuer)
			sub[name] = Variants.flag(a["on"])
			if name == "truth":
				sub["layers"] = a.get("layers", PackedStringArray())
			subscriptions[issuer] = sub
			return _ok("%s %s" % [name, "on" if Variants.flag(a["on"]) else "off"])
		"tuning":
			var errors: Array[String] = []
			if str(a["action"]) == "reload":
				errors = Tuning.reload_now()
			else:
				errors = Tuning.set_dev_override(str(a["key"]), _value_of(str(a["value"])))
			return _ok("tuning %s" % a["action"]) if errors.is_empty() else {"ok": false, "text": "; ".join(errors)}
		"ring_override":
			WorldCoords.ring_override = int(Variants.number(a["ring"]))
			return _ok("ring lookups: %s" % ("as the map says" if WorldCoords.ring_override < 0 else "ring %d" % WorldCoords.ring_override))
		"seed":
			return _ok("run seed %s" % LbHash.to_hex(run.header.run_seed))
		"listener_mode":
			return _no("a client setting (use the client console)")
		"deafen":
			if run.deafen == null:
				return _no("no deafening (SND-04)")
			var slot: int = _slot_of(run, a["who"], issuer)
			if slot < 0:
				return _err("no such miner")
			run.deafen.deafen(run, slot, float(Variants.number(a["seconds"])))
			return _ok("slot %d deafened" % slot)
	return _err("unknown command")


func _spawn(run: RunState, a: Dictionary, issuer: int) -> Dictionary:
	var at: Variant = _tile_of(run, a["at"], issuer)
	if at == null:
		return _err("'here' needs a miner (a client console)")
	var tile: Vector2i = at
	var what: String = str(a["what"])
	if what == "item":
		if run.inventory == null:
			return _no("no items (MNR-04)")
		var key: String = str(a["item"]).to_upper()
		if not ItemKinds.Kind.has(key) or key == "NONE":
			return _err("no item kind '%s'" % a["item"])
		var open: Variant = nearest_open(run, tile)
		if open == null:
			return _err("no open tile near %s" % tile)
		var open_at: Vector2i = open
		var kind: ItemKinds.Kind = int(Variants.number(ItemKinds.Kind[key])) as ItemKinds.Kind
		var item: Item = run.inventory.world.make(kind)
		run.inventory.world.put(run, item, Vector2(open_at) + Vector2(0.5, 0.5), &"debug_spawn")
		return _ok("%s at %s" % [what, open_at])
	if run.creatures == null:
		return _no("no creatures (CRT-01)")
	var kind: WorldIds.EntityKind = KINDS[what]
	var c: Creature = run.creatures.creature_of_kind(kind)
	if c == null and run.creatures.suspended.has(kind):
		c = run.creatures.resume(run, kind)
	var open_tile: Variant = nearest_open(run, tile)
	if open_tile == null:
		return _err("no open tile near %s" % tile)
	var target: Vector2i = open_tile
	if c != null:
		run.creatures.move_to(run, c, Vector2(target) + Vector2(0.5, 0.5))
	else:
		c = _new_creature(kind)
		if c == null:
			return _no("the %s arrives with its CRT ticket" % what)
		var error: Error = run.creatures.place_now(run, c, target)
		if error != OK:
			return _err("refused (%s)" % ("disabled in creatures.enabled" if error == ERR_UNAVAILABLE else error_string(error)))
	var state: String = str(a.get("state", ""))
	if not state.is_empty():
		if not c.states.has(StringName(state)):
			return _err("the %s has no state '%s' (%s)" % [what, state, ", ".join(PackedStringArray(c.states.keys()))])
		c.state = c.states[StringName(state)]
	return _ok("%s at %s, %s; %d of its kind" % [what, target, c.state.name, run.creatures.count_of(kind)])


func _new_creature(kind: WorldIds.EntityKind) -> Creature:
	match kind:
		WorldIds.EntityKind.MOTH:
			return Moth.new()
		WorldIds.EntityKind.TAPPER:
			return Tapper.new()
		WorldIds.EntityKind.STYTHE:
			return StytheCreature.new()
	return null


## DIR-03: the Pull of one miner (by slot, or "me") or of every tracked one.
func _set_pull(run: RunState, a: Dictionary, issuer: int) -> Dictionary:
	if run.pull == null:
		return _no("the Director is off in this run")
	var value: float = float(Variants.number(a["value"]))
	var miners: Array[int] = []
	if a["who"] is String and str(a["who"]) == "all":
		miners = Draught.conscious_humans(run)
	else:
		var slot: int = _slot_of(run, a["who"], issuer)
		if slot < 0:
			return _no("no miner in that slot")
		miners.append(run.movement.miner(slot).entity_id)
	var done: int = 0
	for e: int in miners:
		if run.pull.set_value(e, value):
			done += 1
	if done == 0:
		return _no("nobody there holds a Pull (Hands, the fallen and the dead hold none)")
	return _ok("Pull %.0f for %d miner%s" % [value, done, "" if done == 1 else "s"])


## DIR-01: the Draught intensity of one miner (by slot, or "me") or of every tracked one.
func _set_intensity(run: RunState, a: Dictionary, issuer: int) -> Dictionary:
	if run.draught == null:
		return _no("the Director is off in this run")
	var value: float = float(Variants.number(a["value"]))
	var miners: Array[int] = []
	if a["who"] is String and str(a["who"]) == "all":
		miners = run.draught.tracked_miners(run)
	else:
		var slot: int = _slot_of(run, a["who"], issuer)
		if slot < 0:
			return _no("no miner in that slot")
		miners.append(run.movement.miner(slot).entity_id)
	var done: int = 0
	for e: int in miners:
		if run.draught.set_intensity(e, value):
			done += 1
	if done == 0:
		return _no("nobody there holds an intensity (Hands, the fallen and the dead hold none)")
	return _ok("intensity %.0f for %d miner%s" % [value, done, "" if done == 1 else "s"])


func _teleport(run: RunState, a: Dictionary, issuer: int) -> Dictionary:
	var slot: int = _slot_of(run, a["who"], issuer)
	if slot < 0 or run.movement == null or run.movement.miner(slot) == null:
		return _err("no such miner")
	var wanted: Vector2i = a["tile"]
	var open: Variant = nearest_open(run, wanted)
	if open == null:
		return _err("no open tile near %s" % wanted)
	var open_at: Vector2i = open
	var m: MovementSystem.Miner = run.movement.miner(slot)
	run.movement.place(run, m.entity_id, Vector2(open_at) + Vector2(0.5, 0.5))
	return _ok("slot %d at %s" % [slot, open_at])


func _creatures(run: RunState, a: Dictionary) -> Dictionary:
	if run.creatures == null:
		return _no("no creatures (CRT-01)")
	var kinds: Array = KINDS.values() if str(a["kind"]).is_empty() else [KINDS[str(a["kind"])]]
	var done: PackedStringArray = PackedStringArray()
	for raw: Variant in kinds:
		var kind: WorldIds.EntityKind = raw
		if Variants.flag(a["on"]):
			var back: Creature = run.creatures.resume(run, kind)
			if back != null:
				done.append(str(back.kind_name()))
		else:
			var c: Creature = run.creatures.creature_of_kind(kind)
			if c != null:
				if not run.creatures.suspend(run, c):
					return _err("the %s is busy (grabbing or winding up); try freeze_ai" % c.kind_name())
				done.append(str(c.kind_name()))
	return _ok("%s: %s" % ["on" if Variants.flag(a["on"]) else "off", ", ".join(done) if not done.is_empty() else "none"])


## The open tile nearest `tile` (itself if open), within OPEN_SEARCH_TILES; null if none.
static func nearest_open(run: RunState, tile: Vector2i) -> Variant:
	if run.mine == null:
		return tile
	for r: int in OPEN_SEARCH_TILES + 1:
		var best: Variant = null
		var best_d: float = INF
		for dy: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var t: Vector2i = tile + Vector2i(dx, dy)
				var d: float = Vector2(dx, dy).length()
				if d < best_d and run.mine.native.is_walkable(t):
					best = t
					best_d = d
		if best != null:
			return best
	return null


func _slot_of(run: RunState, who: Variant, issuer: int) -> int:
	if who is String and str(who) == "me":
		return issuer
	var slot: int = int(Variants.number(who))
	return slot if run.movement != null and run.movement.miner(slot) != null else -1


func _tile_of(run: RunState, at: Variant, issuer: int) -> Variant:
	if at is Vector2i:
		return at
	if issuer < 0 or run.movement == null or run.movement.miner(issuer) == null:
		return null
	var m: MovementSystem.Miner = run.movement.miner(issuer)
	return Vector2i(floori(m.state.x), floori(m.state.y))


static func _value_of(text: String) -> Variant:
	if text.is_valid_int():
		return text.to_int()
	if text.is_valid_float():
		return text.to_float()
	if text == "true" or text == "false":
		return text == "true"
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed != null else text


func _reply(slot: int, reply: Dictionary) -> void:
	for s: Sessions.Session in net.sessions.welcomed():
		if s.slot == slot and s.debug:
			net.transport.send(s.peer, Lane.Id.DEBUG, Protocol.frame(Protocol.Msg.DEBUG_REPLY, DebugMessages.encode(reply)))


static func _ok(text: String) -> Dictionary:
	return {"ok": true, "text": text}


static func _err(text: String) -> Dictionary:
	return {"ok": false, "text": text}


static func _no(why: String) -> Dictionary:
	return {"ok": false, "text": "%s: %s" % [NOT_AVAILABLE, why]}
