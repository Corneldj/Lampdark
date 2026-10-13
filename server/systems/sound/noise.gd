class_name NoiseSystem
extends SimSystem
## SND-02's one emission call for every sound (run.noise). Systems call emit() or
## start_periodic() during their stage; at stage 11 (ROAD_GRAPH) the queued events, in order,
## propagate through SND-01's Road Graph and are dispatched: creature listeners (CRT-08, after
## SND-16's Fan filter), player deliveries (SND-03), the collapse hook, then the true-world event
## log (NET-07's run record). Event ids rise through the run. Server-only: true sources and
## entities never leave it; client_record() is what a client may be sent.
##
## The ticket proposed an autoload; a per-run system keeps event ids and emitters in the run's
## state and keeps server code out of client builds.

## One emitted event (server-only).
class Event:
	extends RefCounted
	var id: int = 0
	var tick: int = 0
	var type: NoiseTypes.Type = NoiseTypes.Type.NONE
	var level_np: float = 0.0
	var origins: Array[Vector2i] = []
	## The entity that made it, if any (server-only; never in a client record).
	var source_entity: int = 0
	## SND-13's character voice, for vocal types only.
	var voice_id: int = -1
	var duration_s: float = 0.5
	var struck: bool = false
	var mode: int = RoadGraphService.MODE_AIR
	var deliveries: Array = []
	var collapses: PackedInt64Array = PackedInt64Array()


var catalogue: NoiseCatalogue
var road_graph: RoadGraphService = null
var collapse: CollapseHook
## The true-world event log: every event once, with its true source (NET-07 persists it).
var event_log: Array[Event] = []
## listener id -> true for creature listeners; anything else is a player.
var creature_listeners: Dictionary = {}
## (event: Event, delivery: Dictionary) -> void, for CRT-08's hearing.
var creature_hooks: Array[Callable] = []
## (event: Event, delivery: Dictionary) -> bool; SND-16's Fan filter. Unset passes everything.
var creature_filter: Callable = Callable()
## (listener_id: int, record: Dictionary) -> void, for SND-03's client records.
var player_hooks: Array[Callable] = []
var _queue: Array[Event] = []
var _next_id: int = 1
## handle -> [type, entity id, next tick, opts]
var _periodic: Dictionary = {}
var _next_handle: int = 1
var _run: RunState = null


func _init(graph: RoadGraphService = null) -> void:
	road_graph = graph
	catalogue = NoiseCatalogue.load_default()
	collapse = CollapseHook.new(graph)


func stage() -> int:
	return StageTable.Stage.ROAD_GRAPH


func order() -> int:
	return 10


func system_name() -> String:
	return "noise"


## Emits a sound at a tile. Options: source (entity id, server-only), voice_id (vocal types),
## level_np (required for voice and callouts: the band's np), duration_s, origins
## (Array[Vector2i], several origins at once, e.g. the engine), mode (RoadGraphService.MODE_*).
## An origin in solid rock (the Tapper's taps on a wall face) enters the air at the open floor
## beside it: its walkable neighbours (north, east, south, west) replace it, since the Road Graph
## carries sound only through open tiles.
## Returns the event id, or 0 for an unknown type or a silent level.
func emit(type: NoiseTypes.Type, tile: Vector2i, opts: Dictionary = {}) -> int:
	var e: NoiseCatalogue.Entry = catalogue.entry(type)
	if e == null:
		push_error("NoiseSystem.emit: unknown type %d" % type)
		return 0
	var event: Event = Event.new()
	event.type = type
	event.level_np = float(Variants.number(opts.get("level_np", e.np)))
	if event.level_np <= 0.0:
		if e.np_key.is_empty():
			push_error("NoiseSystem.emit: %s needs level_np (its band's np)" % e.id)
		return 0
	event.id = _next_id
	_next_id += 1
	event.tick = _run.tick if _run != null else 0
	var origins: Array = Variants.array(opts.get("origins", [tile]))
	for raw: Variant in origins:
		var o: Vector2i = raw
		for open: Vector2i in _into_air(o):
			if not event.origins.has(open):
				event.origins.append(open)
	event.source_entity = int(Variants.number(opts.get("source", 0)))
	if e.vocal:
		event.voice_id = int(Variants.number(opts.get("voice_id", -1)))
	elif opts.has("voice_id"):
		push_error("NoiseSystem.emit: %s is not vocal and carries no voice id" % e.id)
	event.duration_s = float(Variants.number(opts.get("duration_s", e.duration_s)))
	event.struck = e.struck
	event.mode = int(Variants.number(opts.get("mode", RoadGraphService.MODE_AIR)))
	_queue.append(event)
	return event.id


## A sound made in solid rock leaves through the open floor beside it; an open tile is itself.
func _into_air(o: Vector2i) -> Array[Vector2i]:
	var mine: Mine = _run.mine if _run != null else null
	if mine == null or mine.native.is_walkable(o):
		return [o] as Array[Vector2i]
	var out: Array[Vector2i] = []
	for d: Vector2i in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		if mine.native.is_walkable(o + d):
			out.append(o + d)
	return out if not out.is_empty() else ([o] as Array[Vector2i])


## Emits a type at its catalogue rate from an entity's tile, from the next stage 11 on.
func start_periodic(type: NoiseTypes.Type, entity_id: int, opts: Dictionary = {}) -> int:
	var e: NoiseCatalogue.Entry = catalogue.entry(type)
	if e == null or e.rate_ticks <= 0:
		push_error("NoiseSystem.start_periodic: %s has no rate" % (e.id if e != null else str(type)))
		return 0
	var handle: int = _next_handle
	_next_handle += 1
	_periodic[handle] = [type, entity_id, -1, opts]
	return handle


func stop_periodic(handle: int) -> void:
	_periodic.erase(handle)


func set_player_listener(id: int, tile: Vector2i) -> void:
	creature_listeners.erase(id)
	if road_graph != null:
		road_graph.set_player_listener(id, tile)


func set_creature_listener(id: int, tile: Vector2i, multiplier: float) -> void:
	creature_listeners[id] = true
	if road_graph != null:
		road_graph.set_creature_listener(id, tile, multiplier)


func remove_listener(id: int) -> void:
	creature_listeners.erase(id)
	if road_graph != null:
		road_graph.remove_listener(id)


func tick(run: RunState) -> void:
	_run = run
	var handles: Array = _periodic.keys()
	handles.sort()
	for raw: Variant in handles:
		var p: Array = _periodic[raw]
		var next_tick: int = p[2]
		if next_tick < 0:
			next_tick = run.tick
		if run.tick < next_tick:
			continue
		var type: NoiseTypes.Type = p[0]
		var entity: SimEntity = run.registry.get_entity(int(Variants.number(p[1])))
		if entity == null:
			_periodic.erase(raw)
			continue
		var opts: Dictionary = Variants.dict(p[3]).duplicate()
		opts["source"] = entity.id
		emit(type, entity.tile(), opts)
		p[2] = next_tick + catalogue.entry(type).rate_ticks
	var queue: Array[Event] = _queue
	_queue = []
	for event: Event in queue:
		event.tick = run.tick
		_dispatch(event)


func _dispatch(event: Event) -> void:
	if road_graph != null:
		event.deliveries = road_graph.propagate(event.id, event.origins, event.level_np, event.mode)
	for raw: Variant in event.deliveries:
		var d: Dictionary = Variants.dict(raw)
		var listener: int = int(Variants.number(d["listener"]))
		if not creature_listeners.has(listener):
			continue
		if creature_filter.is_valid() and not creature_filter.call(event, d):
			continue
		for hook: Callable in creature_hooks:
			hook.call(event, d)
	for raw: Variant in event.deliveries:
		var d: Dictionary = Variants.dict(raw)
		var listener: int = int(Variants.number(d["listener"]))
		if creature_listeners.has(listener):
			continue
		var record: Dictionary = client_record(event, d)
		# NET-08's audit only (SND-03's delivery log): never part of what a client may be told.
		var audit: Dictionary = {"path_tiles": d.get("path_tiles", 0.0), "via": d.get("via", -1)}
		for hook: Callable in player_hooks:
			hook.call(listener, record, audit)
	event.collapses = collapse.on_event(event.id, event.type, event.origins, event.level_np)
	event_log.append(event)


## What a player's client may be told of one delivery (SND-03 encodes it): the type, where it
## seems to come from, how loud it arrives and how long it lasts, and a vocal type's voice.
## Never an entity, a true source or the event's origin.
func client_record(event: Event, delivery: Dictionary) -> Dictionary:
	var record: Dictionary = {
		"event_id": event.id,
		"type": event.type,
		"tick": event.tick,
		"apparent": delivery.get("apparent", Vector2.ZERO),
		"remaining_np": delivery.get("remaining_np", 0.0),
		"level_np": event.level_np,
		"duration_s": event.duration_s,
		# SND-03: a closed portal on the path (already 12 np down) muffles it.
		"muffled": int(Variants.number(delivery.get("closed_portals", 0))) > 0,
	}
	if event.voice_id >= 0:
		record["voice_id"] = event.voice_id
	return record


func write_state(writer: SimStateWriter) -> void:
	writer.put_i64(_next_id)
	writer.put_i64(_next_handle)
	var handles: Array = _periodic.keys()
	handles.sort()
	writer.put_i64(handles.size())
	for raw: Variant in handles:
		var p: Array = _periodic[raw]
		writer.put_i64(int(Variants.number(raw)))
		writer.put_i64(int(Variants.number(p[0])))
		writer.put_i64(int(Variants.number(p[1])))
		writer.put_i64(int(Variants.number(p[2])))
