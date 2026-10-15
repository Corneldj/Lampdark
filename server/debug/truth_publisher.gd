class_name TruthPublisher
extends SimSystem
## FND-08: the truth view's feed. At 5 Hz (Proposed) each debug-granted client that switched the
## truth view on gets the authoritative state around its miner, limited to the layers it chose:
##   entities  every entity within RANGE tiles: server id, kind, position, flags
##   creatures each creature's state, target, guard result on that target, timers, frozen
##   light     the light grid around the miner (a heat map, row-major)
##   vision    the miner's cone (position, facing) and seen set
##   sound     Road Graph events since the last snapshot: type, origins, np and reach
##   director  per miner: Pull, intensity and unheard timers (DIR tickets; "n/a" until then), the
##             crew count and active-hunter cap
##   lies      illusions sent to any client since the last snapshot (CRT-10's lie log)
## Only on the debug lane, never in a normal-stream record. Stage SEND, after Replication. Never
## in the state hash.

const RANGE: int = 20
const HZ: float = 5.0

var net: ServerNet = null
var debug: DebugServer = null
## Snapshots sent (tests).
var sent: int = 0
var _last_event: int = 0
var _lies: Array[Dictionary] = []


func _init(server_net: ServerNet, debug_server: DebugServer) -> void:
	net = server_net
	debug = debug_server


func stage() -> int:
	return StageTable.Stage.SEND


func order() -> int:
	return 50


func system_name() -> String:
	return "truth_publisher"


func hashed() -> bool:
	return false


func tick(run: RunState) -> void:
	if run.replication != null:
		_lies.append_array(run.replication.illusions_sent)
	var every: int = maxi(1, roundi(Tuning.f(&"net.tick_hz") / HZ))
	if run.tick % every != 0:
		return
	var events: Array[Dictionary] = _new_events(run)
	for s: Sessions.Session in net.sessions.welcomed():
		var sub: Dictionary = debug.subscription(s.slot)
		if not s.debug or not Variants.flag(sub.get("truth", false)):
			continue
		var snapshot: Dictionary = build(run, s.slot, PackedStringArray(Variants.array(sub.get("layers", []))), events)
		net.transport.send(s.peer, Lane.Id.DEBUG, Protocol.frame(Protocol.Msg.DEBUG_TRUTH, DebugMessages.encode(snapshot)))
		sent += 1
	_lies.clear()


## One snapshot for `slot`, with only `layers`.
func build(run: RunState, slot: int, layers: PackedStringArray, events: Array[Dictionary] = []) -> Dictionary:
	var centre: Vector2 = Vector2.ZERO
	var m: MovementSystem.Miner = run.movement.miner(slot) if run.movement != null else null
	if m != null:
		centre = Vector2(m.state.x, m.state.y)
	var out: Dictionary = {"tick": run.tick, "centre": centre, "layers": layers}
	if layers.has("entities"):
		var list: Array = []
		for id: int in run.registry.ids():
			var e: SimEntity = run.registry.get_entity(id)
			if e.position.distance_to(centre) <= RANGE:
				list.append({"id": id, "kind": str(WorldIds.EntityKind.find_key(e.kind)).to_lower(), "position": e.position, "flags": e.flags})
		out["entities"] = list
	if layers.has("creatures") and run.creatures != null:
		var list: Array = []
		for c: Creature in run.creatures.creatures:
			var target: int = run.creatures.gate.target_of(c)
			list.append({"id": c.entity_id, "kind": str(c.kind_name()), "position": c.position(run), "state": str(c.state.name) if c.state != null else "",
				"target": target, "guard": run.creatures.guards.holds(run, c.kind, target) if target > 0 else false,
				"retreat_until": c.retreat_until, "frozen": run.creatures.frozen})
		for raw: Variant in run.creatures.suspended.values():
			var held: Array = raw
			var c: Creature = held[0]
			list.append({"id": 0, "kind": str(c.kind_name()), "position": held[1], "state": "suspended", "target": 0, "guard": false,
				"retreat_until": c.retreat_until, "frozen": run.creatures.frozen})
		out["creatures"] = list
	if layers.has("light") and run.light != null:
		var origin: Vector2i = Vector2i(floori(centre.x), floori(centre.y)) - Vector2i(RANGE, RANGE)
		var size: int = RANGE * 2 + 1
		var grid: PackedFloat32Array = PackedFloat32Array()
		grid.resize(size * size)
		for y: int in size:
			for x: int in size:
				grid[y * size + x] = run.light.light_at(origin + Vector2i(x, y))
		out["light"] = {"origin": origin, "size": size, "values": grid}
	if layers.has("vision") and run.vision != null:
		var frame: Dictionary = run.vision.frame_for(slot)
		var tiles: Dictionary = Variants.dict(frame.get("tiles", {}))
		out["vision"] = {"position": centre, "facing": m.state.facing if m != null else 0, "cone_deg": Tuning.f(&"vision.cone_deg"),
			"seen_x": tiles.get("x", PackedInt32Array()), "seen_y": tiles.get("y", PackedInt32Array())}
	if layers.has("sound"):
		out["sound"] = events
	if layers.has("director"):
		var miners: Array = []
		if run.movement != null:
			for s: int in run.movement.miner_slots():
				var mm: MovementSystem.Miner = run.movement.miner(s)
				miners.append({"slot": s, "pull": "n/a (DIR-03)", "intensity": "n/a (DIR-01)", "unheard_s": run.heard.unheard_seconds(s) if run.heard != null else -1.0,
					"unheard_mark_s": Depth.unheard_mark_s(run, mm.entity_id)})
		out["director"] = {"miners": miners, "crew_count": run.crew.count if run.crew != null else -1,
			"active_cap": run.cap.capacity() if run.cap != null else -1}
	if layers.has("lies"):
		out["lies"] = _lies.duplicate()
	return out


func _new_events(run: RunState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if run.noise == null:
		return out
	for e: NoiseSystem.Event in run.noise.event_log:
		if e.id <= _last_event:
			continue
		var reach: float = 0.0
		for d: Variant in e.deliveries:
			reach = maxf(reach, float(Variants.number(Variants.dict(d).get("path_tiles", 0.0))))
		out.append({"id": e.id, "tick": e.tick, "type": NoiseTypes.id_of(e.type), "origins": e.origins, "np": e.level_np, "reach_tiles": reach,
			"listeners": e.deliveries.size()})
		_last_event = e.id
	return out
