class_name RecordReaders
extends RefCounted
## NET-07's readers over the run record. Each returns nothing once the record is discarded.
##  - delayed_view(record, target, delay_s): RSC-04's watching, the target client's received view
##    and the game sounds it was sent, delay_s behind. Frames only: never voice, and never the map
##    table, the Pocket Book or a close-up (they never ride in frames).
##  - victim_view(record, window): the victim's own stream, rebuilt frame by frame from what their
##    client acknowledged, illusions included and marked (RSC-04's view at the fall, RSC-08's replay).
##  - true_view(record, window): every real entity, light source, door and sound of the victim's
##    30x17 frame, tick by tick, with the frame's true light. Served only during Lamp Check, and
##    every call is logged (Gameplay §9.6, §11.10).
## Server-only: nothing here is sent to a client except through RSC-04's re-encoding of the
## delayed view, and RSC-08's replays at Lamp Check.


## Where watching one target has read to: its decoder, the last tick read and the view held.
class Cursor:
	extends RefCounted
	var decoder: FrameDecoder = FrameDecoder.new()
	var done: int = -1
	var tick: int = -1
	var view: ReceivedView = null


## The target's view as of `delay_s` ago: {tick (the frame's), view (ReceivedView), events (the
## game sounds in the frames decoded since the last call)}, or {} when the record has none.
static func delayed_view(record: RunRecord, target: int, delay_s: float) -> Dictionary:
	var run: RunState = record.run_state()
	if record.discarded or run == null:
		return {}
	# The newest frame sent is the last tick's.
	var at: int = run.tick - 1 - roundi(delay_s * 1000.0 / record.tick_ms)
	if at < 0 or at > record.sealed_to():
		return {}
	var c: Cursor = record.watch_cursors.get(target, null)
	if c == null or c.done > at or not _cursor_block_held(record, c):
		c = _start_cursor(record, target, at)
		if c == null:
			return {}
		record.watch_cursors[target] = c
	var events: Array[Dictionary] = []
	while c.done < at:
		var block: RecordBlock = _block_at(record, c.done + 1)
		if block == null:
			break
		var lines: Dictionary = block.stream_ticks(target)
		for raw: Variant in Variants.array(lines.get("f", [])):
			var f: Array = raw
			var t: int = f[0]
			var received: int = f[2]
			if t <= c.done or t > at or received != 1:
				continue
			var bytes: PackedByteArray = f[1]
			var d: FrameDecoder.Decoded = c.decoder.decode(bytes)
			if d.ok:
				c.tick = d.tick
				c.view = d.view
				events.append_array(d.events)
		c.done = mini(at, block.last())
	if c.view == null:
		return {}
	return {"tick": c.tick, "view": c.view, "events": events}


## Every frame the victim's client received in the window, oldest first: {tick, view, events,
## arrival_ms (the estimated delay from send to arrival), illusions (the numbers of the events
## that were CRT-10's lies)}.
static func victim_view(record: RunRecord, window: RecordWindow) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if record.discarded or window == null or not window.sealed or window.slot < 0:
		return out
	var decoder: FrameDecoder = null
	for b: RecordBlock in window.blocks:
		if decoder == null:
			decoder = _seeded_decoder(b.stream_keyframe(window.slot))
		var lines: Dictionary = b.stream_ticks(window.slot)
		for raw: Variant in Variants.array(lines.get("f", [])):
			var f: Array = raw
			var t: int = f[0]
			var received: int = f[2]
			if received != 1:
				continue
			var bytes: PackedByteArray = f[1]
			var d: FrameDecoder.Decoded = decoder.decode(bytes)
			if not d.ok or t < window.start or t > window.end:
				continue
			var arrival: int = f[3]
			var numbers: PackedInt32Array = f[4]
			out.append({"tick": t, "view": d.view, "events": d.events, "arrival_ms": arrival, "illusions": numbers})
	return out


## The true view of the window, tick by tick: {tick, origin, size, light (one byte a tile, row by
## row), entities [{id, kind, position, flags}], sources [{id, kind, owner, flags, position, radius,
## peak}], doors [{door, open, centre}], sounds (dispatched this tick from inside the frame),
## voice [[speaker, band, listener bits]], lies (the victim's)}. Nothing unless the run is in
## Lamp Check; every call is logged.
static func true_view(record: RunRecord, window: RecordWindow) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var run: RunState = record.run_state()
	var phase: RunState.Phase = run.phase if run != null else RunState.Phase.PLAYING
	var allowed: bool = not record.discarded and window != null and window.sealed and phase == RunState.Phase.LAMP_CHECK
	var line: String = "run record: true view of window %d %s (phase %s)" % [window.id if window != null else -1,
		"served" if allowed else "refused", RunState.Phase.keys()[phase]]
	record.true_view_log.append(line)
	Log.info(line)
	if not allowed:
		return out
	var entities: Dictionary = {}
	var sources: Dictionary = {}
	var doors: Dictionary = {}
	var started: bool = false
	for b: RecordBlock in window.blocks:
		if not started:
			var key: Dictionary = b.auth_keyframe()
			if key.is_empty():
				continue
			entities = _entities_from(key)
			sources = Variants.dict(key.get("sources", {}))
			doors = Variants.dict(key.get("doors", {})).duplicate(true)
			started = true
		var light: Dictionary = {}
		for raw: Variant in Variants.array(b.stream_ticks(window.slot).get("l", [])):
			var l: Array = raw
			light[l[0]] = l
		for raw: Variant in b.auth_ticks():
			var e: Dictionary = raw
			var t: int = e["t"]
			_apply(e, entities, doors)
			if e.has("s"):
				sources = e["s"]
			if t < window.start or t > window.end:
				continue
			var light_line: Array = light.get(t, [])
			out.append(_frame(record, window, t, e, entities, sources, doors, light_line))
	return out


## CRT-10's lie log entries between two ticks for one slot (all slots for -1), from the ring.
static func lies(record: RunRecord, from_tick: int, to_tick: int, slot: int = -1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if record.discarded:
		return out
	for b: RecordBlock in record.blocks_between(from_tick, to_tick):
		out.append_array(_lies_in(b, from_tick, to_tick, slot))
	return out


## The same from a window (they outlive the ring).
static func window_lies(record: RunRecord, window: RecordWindow) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if record.discarded or window == null:
		return out
	for b: RecordBlock in window.blocks:
		out.append_array(_lies_in(b, window.start, window.end, window.slot))
	return out


static func _lies_in(b: RecordBlock, from_tick: int, to_tick: int, slot: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw: Variant in b.auth_ticks():
		var e: Dictionary = raw
		var t: int = e["t"]
		if t < from_tick or t > to_tick:
			continue
		for lie: Variant in Variants.array(e.get("lie", [])):
			var entry: Dictionary = Variants.dict(lie)
			if slot < 0 or int(Variants.number(entry.get("slot", -1))) == slot:
				out.append(entry)
	return out


static func _seeded_decoder(key: Dictionary) -> FrameDecoder:
	var decoder: FrameDecoder = FrameDecoder.new()
	var views: Dictionary = Variants.dict(key.get("views", {}))
	for raw: Variant in views.keys():
		var t: int = raw
		decoder.history[t] = ReceivedView.from_dict(Variants.dict(views[raw]))
	return decoder


static func _start_cursor(record: RunRecord, target: int, at: int) -> Cursor:
	var block: RecordBlock = _block_at(record, at)
	if block == null:
		return null
	var key: Dictionary = block.stream_keyframe(target)
	var c: Cursor = Cursor.new()
	c.decoder = _seeded_decoder(key)
	c.done = block.start - 1
	var held: int = int(Variants.number(key.get("held", -1)))
	if c.decoder.history.has(held):
		c.tick = held
		c.view = c.decoder.history[held]
	return c


## A cursor reads on only while the ring still holds the block after the one it finished.
static func _cursor_block_held(record: RunRecord, c: Cursor) -> bool:
	return not record.ring.is_empty() and record.ring[0].start <= c.done + 1


static func _block_at(record: RunRecord, t: int) -> RecordBlock:
	for b: RecordBlock in record.ring:
		if b.overlaps(t, t):
			return b
	return null


static func _entities_from(key: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var ids: PackedInt64Array = key.get("ids", PackedInt64Array())
	var kinds: PackedInt32Array = key.get("kinds", PackedInt32Array())
	var xy: PackedFloat64Array = key.get("xy", PackedFloat64Array())
	var flags: PackedInt32Array = key.get("flags", PackedInt32Array())
	for i: int in ids.size():
		out[ids[i]] = {"id": ids[i], "kind": kinds[i], "position": Vector2(xy[2 * i], xy[2 * i + 1]), "flags": flags[i]}
	return out


static func _apply(e: Dictionary, entities: Dictionary, doors: Dictionary) -> void:
	for raw: Variant in Variants.array(e.get("c", [])):
		var c: Array = raw
		var id: int = c[0]
		entities[id] = {"id": id, "kind": c[1], "position": Vector2(float(Variants.number(c[2])), float(Variants.number(c[3]))), "flags": c[4]}
	if e.has("m"):
		var m: Array = e["m"]
		var ids: PackedInt32Array = m[0]
		var xy: PackedFloat32Array = m[1]
		for i: int in ids.size():
			if entities.has(ids[i]):
				var ent: Dictionary = entities[ids[i]]
				ent["position"] = Vector2(xy[2 * i], xy[2 * i + 1])
	if e.has("x"):
		var gone: PackedInt32Array = e["x"]
		for id: int in gone:
			entities.erase(id)
	for raw: Variant in Variants.array(e.get("fl", [])):
		var f: Array = raw
		var id: int = f[0]
		if entities.has(id):
			var ent: Dictionary = entities[id]
			ent["flags"] = f[1]
	for raw: Variant in Variants.array(e.get("d", [])):
		var d: Array = raw
		var key: String = d[0]
		var was: Array = Variants.array(doors.get(key, [false, Vector2.ZERO]))
		doors[key] = [d[1], was[1] if was.size() > 1 else Vector2.ZERO]


static func _frame(record: RunRecord, window: RecordWindow, t: int, e: Dictionary, entities: Dictionary, sources: Dictionary,
		doors: Dictionary, light_line: Array) -> Dictionary:
	var origin: Vector2i
	if light_line.size() == 3:
		origin = light_line[1]
	else:
		var me: Dictionary = Variants.dict(entities.get(window.entity, {}))
		var p: Vector2 = me.get("position", Vector2.ZERO)
		origin = Vector2i(floori(p.x), floori(p.y)) - Vector2i(floori(record.frame_size.x / 2.0), floori(record.frame_size.y / 2.0))
	var rect: Rect2 = Rect2(Vector2(origin), Vector2(record.frame_size))
	var seen: Array[Dictionary] = []
	var ids: Array = entities.keys()
	ids.sort()
	for raw: Variant in ids:
		var ent: Dictionary = entities[raw]
		var p: Vector2 = ent["position"]
		if rect.has_point(p):
			seen.append(ent.duplicate())
	var lit: Array[Dictionary] = []
	var sids: PackedInt64Array = sources.get("ids", PackedInt64Array())
	var sxy: PackedFloat64Array = sources.get("xy", PackedFloat64Array())
	var radius: PackedFloat64Array = sources.get("radius", PackedFloat64Array())
	for i: int in sids.size():
		var at: Vector2 = Vector2(sxy[2 * i], sxy[2 * i + 1])
		if rect.grow(radius[i]).has_point(at):
			lit.append({"id": sids[i], "kind": _kind_of(sources, i),
				"owner": _at64(sources, "owners", i), "flags": _at32(sources, "flags", i), "position": at, "radius": radius[i],
				"peak": _atf(sources, "peak", i)})
	var shut: Array[Dictionary] = []
	var keys: Array = doors.keys()
	keys.sort()
	for raw: Variant in keys:
		var d: Array = Variants.array(doors[raw])
		var c: Vector2 = d[1]
		if rect.has_point(c):
			shut.append({"door": raw, "open": d[0], "centre": c})
	var sounds: Array = []
	for raw: Variant in Variants.array(e.get("n", [])):
		var s: Dictionary = raw
		for o: Variant in Variants.array(s.get("origins", [])):
			var tile: Vector2i = o
			if rect.has_point(Vector2(tile) + Vector2(0.5, 0.5)):
				sounds.append(s)
				break
	var mine: Array = []
	for raw: Variant in Variants.array(e.get("lie", [])):
		var lie: Dictionary = Variants.dict(raw)
		if int(Variants.number(lie.get("slot", -1))) == window.slot:
			mine.append(lie)
	var light: PackedByteArray = light_line[2] if light_line.size() == 3 else PackedByteArray()
	return {"tick": t, "origin": origin, "size": record.frame_size, "light": light, "entities": seen, "sources": lit, "doors": shut,
		"sounds": sounds, "voice": Variants.array(e.get("v", [])), "lies": mine}


static func _kind_of(sources: Dictionary, i: int) -> String:
	var kinds: PackedStringArray = sources.get("kinds", PackedStringArray())
	return kinds[i] if i < kinds.size() else ""


static func _at64(sources: Dictionary, key: String, i: int) -> int:
	var a: PackedInt64Array = sources.get(key, PackedInt64Array())
	return a[i] if i < a.size() else 0


static func _at32(sources: Dictionary, key: String, i: int) -> int:
	var a: PackedInt32Array = sources.get(key, PackedInt32Array())
	return a[i] if i < a.size() else 0


static func _atf(sources: Dictionary, key: String, i: int) -> float:
	var a: PackedFloat64Array = sources.get(key, PackedFloat64Array())
	return a[i] if i < a.size() else 0.0
