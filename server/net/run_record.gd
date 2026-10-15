class_name RunRecord
extends SimSystem
## NET-07's run record (stage RECORD, after the falls are emitted): the server's faithful, bounded
## memory of the run (GDD §15.3, §15.7). It keeps every client's frames as sent (NET-04's stream
## tap), which of them arrived (NET-03's acks) and when, the true light of each client's 30x17
## frame, a decoded view keyframe every net.record_keyframe_s, the authoritative track (an entity,
## light-source and door keyframe, then each tick's committed changes, sounds, voice bands and
## logs), and the lie log CRT-10 writes. Never audio: a voice frame is its band, speaker and
## listeners (GDD §15.6).
##
## The rolling ring keeps net.record_window_s of sealed blocks. A fall, a death and each miner's
## first illusion of the run pin a RecordWindow that outlives the ring. If the ring and the
## windows together pass net.record_memory_mb, the oldest windows' keyframes thin from 2 s to 4 s
## (logged; a window is never dropped). Everything is discarded when Lamp Check ends, and every
## reader then returns nothing. RecordReaders serves it. Outside the state hash; server-only.

const SEAL_MARGIN_S: float = 1.0

## The ticks a keyframe interval spans, and how long the ring is.
var block_ticks: int = 40
var ring_ticks: int = 12000
var window_before_ticks: int = 300
var window_tail_ticks: int = 40
var budget_bytes: int = 48 * 1024 * 1024
## A block seals once every frame in it is acknowledged or can no longer be.
var seal_lag_ticks: int = 53
var tick_ms: float = 50.0
## The client frame the true light is kept for (camera.view_tiles_*: 30x17).
var frame_size: Vector2i = Vector2i(30, 17)

## Sealed blocks, oldest first.
var ring: Array[RecordBlock] = []
## Pinned windows, in pin order.
var windows: Array[RecordWindow] = []
## RSC-07's fact extractor (a stub until then): (run, window) -> Dictionary.
var fact_extractor: Callable = func(_at: RunState, _w: RecordWindow) -> Dictionary: return {}
## True after Lamp Check ends: nothing is held and every reader returns nothing.
var discarded: bool = false
## Counters for tests and the log: baselines the encoder no longer held when a keyframe needed
## them, and acknowledgements that came after their frame was sealed as lost.
var keyframe_misses: int = 0
var late_acks: int = 0
var thinning_log: Array[String] = []
## Every true-view call, served or refused (RecordReaders logs them too).
var true_view_log: Array[String] = []
## RecordReaders.Cursor for watching, by target slot.
var watch_cursors: Dictionary = {}

var _run: RunState = null
var _net: ServerNet = null
## The block being filled: its keyframe and its ticks, and each slot's light and rtt lines.
var _open_start: int = -1
var _open_key: Dictionary = {}
var _open_ticks: Array = []
var _open_streams: Dictionary = {}
## Blocks whose ticks are done but whose frames may still be acknowledged: [start, key, ticks, streams].
var _awaiting: Array[Array] = []
## slot -> {frame tick: [bytes, state (-1 waiting, 1 received, 0 lost), arrival_ms, illusion numbers]}
var _frames: Dictionary = {}
## slot -> the newest frame tick sent, and the newest acknowledged.
var _last_sent: Dictionary = {}
var _newest_ack: Dictionary = {}
## slot -> {frame tick: true} for frames sent and not yet acknowledged.
var _unacked: Dictionary = {}
## slot -> {block start: its keyframe so far}
var _keys: Dictionary = {}
## The first block's first tick: blocks run from it every block_ticks.
var _origin: int = -1
## slot -> {frame tick: true} for frames sealed as lost, while an acknowledgement could still name them.
var _sealed_lost: Dictionary = {}
## This tick's events, gathered by signals before stage RECORD.
var _voice: Array = []
var _creature_log: Array = []
var _lies: Array = []
var _falls: Array = []
var _deaths: Array = []
var _decisions_seen: int = 0
## MNR-16: shots already written.
var _shots_seen: int = 0
var _doors_seen: int = 0
var _last_sound: int = 0
var _last_sources: Dictionary = {}
var _last_ids: PackedInt64Array = PackedInt64Array()
var _last_flags: PackedInt32Array = PackedInt32Array()
var _first_illusion: Dictionary = {}
## grab id -> the tick it began (a drag's window starts at the grab).
var _grab_began: Dictionary = {}
var _next_window: int = 1
var _pending_windows: Array[RecordWindow] = []
var _open_bytes: int = 0
var _ring_bytes: int = 0
var _windows_bytes: int = 0
## The block being sealed, a part a tick: {item (as in _awaiting), block, slots still to pack}.
var _sealing: Dictionary = {}


func stage() -> int:
	return StageTable.Stage.RECORD


func order() -> int:
	return 40


func system_name() -> String:
	return "run_record"


## Watching and replays only: never part of the state hash.
func hashed() -> bool:
	return false


func bind(run: RunState, net: ServerNet) -> void:
	_run = run
	_net = net
	var hz: float = Tuning.f(&"net.tick_hz")
	tick_ms = 1000.0 / hz
	block_ticks = maxi(1, roundi(Tuning.f(&"net.record_keyframe_s") * hz))
	ring_ticks = roundi(Tuning.f(&"net.record_window_s") * hz)
	window_before_ticks = roundi(Tuning.f(&"net.record_event_window_s") * hz)
	window_tail_ticks = roundi(Tuning.f(&"net.record_tail_s") * hz)
	budget_bytes = roundi(Tuning.f(&"net.record_memory_mb") * 1024.0 * 1024.0)
	seal_lag_ticks = Tuning.i(&"net.ack_history_frames") + 1 + roundi(SEAL_MARGIN_S * hz)
	if Tuning.current.has_key(&"camera.view_tiles_wide"):
		frame_size = Vector2i(ceili(Tuning.f(&"camera.view_tiles_wide")), ceili(Tuning.f(&"camera.view_tiles_high")))
	if run.replication != null:
		run.replication.tap.sent.connect(_on_sent)
		run.replication.acked.connect(_on_acked)
	if run.voice != null:
		run.voice.frame_routed.connect(_on_voice_frame)
	if run.creatures != null:
		run.creatures.log.logged.connect(func(entry: Dictionary) -> void: _creature_log.append(_plain(entry)))
	if run.falls != null:
		run.falls.fell.connect(_on_fell)
	if run.miner_state != null:
		run.miner_state.state_changed.connect(_on_state_changed)
	if run.holds != null:
		run.holds.grab_begun.connect(func(grab_id: int, _k: GrabHold.Kind, _c: int, _v: int) -> void: _grab_began[grab_id] = _run.tick)
	run.phase_changed.connect(_on_phase_changed)


## CRT-10 writes the lie log here: each entry a plain dictionary with at least its tick and the
## target's slot. The record keeps it and copies it into the windows; RSC-08 reads it at Lamp Check.
func lie_log_append(entry: Dictionary) -> void:
	if discarded:
		return
	var e: Dictionary = _plain(entry)
	if not e.has("tick"):
		e["tick"] = _run.tick
	_lies.append(e)


## NET-09: every window, as plain values, for snapshots and knock-off saves.
func export_windows() -> Array:
	var out: Array = []
	for w: RecordWindow in windows:
		if w.sealed:
			out.append(w.to_dict())
	return out


## NET-09: windows saved by an earlier session (a Full run's Lamp Check can replay its falls).
func import_windows(saved: Array) -> void:
	if discarded:
		return
	for raw: Variant in saved:
		var w: RecordWindow = RecordWindow.from_dict(Variants.dict(raw))
		windows.append(w)
		_windows_bytes += w.size()
		_next_window = maxi(_next_window, w.id + 1)


func run_state() -> RunState:
	return _run


## Bytes held: the ring, the windows, and the open blocks not yet compressed.
func memory_bytes() -> int:
	return ring_bytes() + windows_bytes() + _open_bytes


func ring_bytes() -> int:
	return _ring_bytes


func windows_bytes() -> int:
	return _windows_bytes


## The ring's sealed blocks overlapping [from_tick, to_tick], oldest first.
func blocks_between(from_tick: int, to_tick: int) -> Array[RecordBlock]:
	var out: Array[RecordBlock] = []
	for b: RecordBlock in ring:
		if b.overlaps(from_tick, to_tick):
			out.append(b)
	return out


## The newest tick the ring holds sealed, or -1.
func sealed_to() -> int:
	return ring[-1].last() if not ring.is_empty() else -1


func tick(run: RunState) -> void:
	if discarded:
		return
	_run = run
	if _open_start < 0:
		_open_block(run)
	_open_ticks.append(_tick_entry(run))
	_record_light(run)
	_note_illusions(run)
	if run.tick + 1 >= _open_start + block_ticks:
		_awaiting.append([_open_start, _open_key, _open_ticks, _open_streams])
		_open_start = -1
	if not _sealing.is_empty():
		_seal_step()
	elif not _awaiting.is_empty() and run.tick >= _awaiting_start() + block_ticks - 1 + seal_lag_ticks:
		var item: Array = _awaiting.pop_front()
		_sealing = {"item": item, "block": null, "slots": _slots_for(item)}


func _awaiting_start() -> int:
	var first: int = _awaiting[0][0]
	return first


## Lamp Check's end: frees everything; every reader returns nothing from now on.
func discard() -> void:
	ring.clear()
	windows.clear()
	_pending_windows.clear()
	_awaiting.clear()
	_frames.clear()
	_keys.clear()
	_unacked.clear()
	watch_cursors.clear()
	_open_key = {}
	_open_ticks = []
	_open_streams = {}
	_open_start = -1
	_open_bytes = 0
	_ring_bytes = 0
	_windows_bytes = 0
	_sealing = {}
	_lies.clear()
	_sealed_lost.clear()
	discarded = true
	Log.info("run record: discarded at Lamp Check's end (tick %d)" % (_run.tick if _run != null else -1))


func _on_phase_changed(phase: RunState.Phase) -> void:
	if phase == RunState.Phase.ENDED and not discarded:
		discard()



func _on_sent(slot: int, at_tick: int, bytes: PackedByteArray) -> void:
	if discarded:
		return
	_key_views(slot, at_tick, bytes)
	var per: Dictionary = _frames.get(slot, {})
	per[at_tick] = [bytes, -1, -1, PackedInt32Array()]
	_frames[slot] = per
	var waiting: Dictionary = _unacked.get(slot, {})
	waiting[at_tick] = true
	_unacked[slot] = waiting
	_last_sent[slot] = at_tick
	_open_bytes += bytes.size()


## NET-03's acknowledgement. The newest frame's arrival on the client is estimated from the ack's
## receive delay and half the RTT (Proposed); the others in its bitmask at half the RTT.
func _on_acked(slot: int, now: int, ack16: int, bits: int, recv_delay: int) -> void:
	if discarded or not _last_sent.has(slot):
		return
	var sent: int = _last_sent[slot]
	var newest: int = sent - ((sent - ack16) & 0xFFFF)
	var half_rtt: float = _rtt_ms(slot) / 2.0
	var arrival: int = maxi(0, roundi((now - newest - 1) * tick_ms - half_rtt - recv_delay * 2.0))
	_mark(slot, newest, arrival)
	# Only frames still unacknowledged (or sealed as lost) can change: a few, not all 32.
	for pending: Dictionary in [_unacked.get(slot, {}), _sealed_lost.get(slot, {})]:
		for raw: Variant in pending.keys():
			var t: int = raw
			var i: int = newest - 1 - t
			if i >= 0 and i < 32 and (bits >> i) & 1:
				_mark(slot, t, roundi(half_rtt))
	var before: int = _newest_ack.get(slot, -1)
	_newest_ack[slot] = maxi(before, newest)


func _mark(slot: int, frame_tick: int, arrival_ms: int) -> void:
	var per: Dictionary = _frames.get(slot, {})
	if not per.has(frame_tick):
		var lost: Dictionary = _sealed_lost.get(slot, {})
		if lost.has(frame_tick):
			late_acks += 1
			lost.erase(frame_tick)
		return
	var f: Array = per[frame_tick]
	var state: int = f[1]
	if state != 1:
		f[1] = 1
		f[2] = arrival_ms
		Variants.dict(_unacked.get(slot, {})).erase(frame_tick)


func _on_voice_frame(slot: int, band: int, listeners: PackedInt32Array) -> void:
	if discarded:
		return
	var mask: int = 0
	for l: int in listeners:
		mask |= 1 << l
	_voice.append([slot, band, mask])


func _on_fell(record: Dictionary) -> void:
	_falls.append(_plain(record))
	var cause: int = int(Variants.number(record.get("tick", _run.tick)))
	if int(Variants.number(record.get("cause", -1))) == FallCause.Cause.DRAG and record.has("grab_id"):
		var began: int = _grab_began.get(int(Variants.number(record["grab_id"])), cause)
		cause = began
	_pin(RecordWindow.Kind.FALL, int(Variants.number(record.get("miner_id", 0))), cause, record)


func _on_state_changed(entity: int, _old: int, new: int, cause: String) -> void:
	if new == MinerTransitions.Life.DEAD and _run != null:
		var d: Dictionary = {"miner_id": entity, "cause_name": cause, "tick": _run.tick}
		_deaths.append(d)
		_pin(RecordWindow.Kind.DEATH, entity, _run.tick, d)


## CRT-10's illusions as NET-04 sent them this tick: the first each miner hears pins a window.
func _note_illusions(run: RunState) -> void:
	if run.replication == null:
		return
	for item: Dictionary in run.replication.illusions_sent:
		var slot: int = int(Variants.number(item["slot"]))
		var per: Dictionary = _frames.get(slot, {})
		if per.has(run.tick):
			var f: Array = per[run.tick]
			var numbers: PackedInt32Array = f[3]
			numbers.append(int(Variants.number(item["number"])))
			f[3] = numbers
		if not _first_illusion.has(slot):
			_first_illusion[slot] = run.tick
			var entity: int = _entity_of(run, slot)
			var detail: Dictionary = _plain(item)
			_pin(RecordWindow.Kind.FIRST_ILLUSION, entity, run.tick, detail)



func _open_block(run: RunState) -> void:
	_open_start = run.tick
	if _origin < 0:
		_origin = run.tick
	var m: Dictionary = run.registry.packed_mirror()
	_open_key = {"tick": run.tick, "ids": m["ids"], "kinds": m["kinds"], "xy": m["xy"], "flags": m["flags"],
		"sources": run.light.grid.sources_packed() if run.light != null else {}, "doors": _doors(run)}
	_last_ids = m["ids"]
	_last_flags = m["flags"]
	_open_ticks = []
	_open_streams = {}


func _doors(run: RunState) -> Dictionary:
	var out: Dictionary = {}
	if run.air_doors == null:
		return out
	for raw: Variant in run.air_doors.doors.keys():
		var d: AirDoorSystem.Door = run.air_doors.doors[raw]
		out[d.key()] = [d.open, d.centre()]
	return out


func _tick_entry(run: RunState) -> Dictionary:
	var e: Dictionary = {"t": run.tick}
	var moved_ids: PackedInt32Array = PackedInt32Array()
	var moved_xy: PackedFloat32Array = PackedFloat32Array()
	var created: Array = []
	var destroyed: PackedInt32Array = PackedInt32Array()
	for c: ChangeFeed.Change in run.feed.changes():
		match c.kind:
			ChangeFeed.Kind.ENTITY_MOVED:
				var p: Vector2 = c.data.get("position", Vector2.ZERO)
				moved_ids.append(c.entity)
				moved_xy.append(p.x)
				moved_xy.append(p.y)
			ChangeFeed.Kind.ENTITY_CREATED:
				var ent: SimEntity = run.registry.get_entity(c.entity)
				if ent != null:
					created.append([c.entity, ent.kind, ent.position.x, ent.position.y, ent.flags])
			ChangeFeed.Kind.ENTITY_DESTROYED:
				destroyed.append(c.entity)
	if not moved_ids.is_empty():
		e["m"] = [moved_ids, moved_xy]
	if not created.is_empty():
		e["c"] = created
	if not destroyed.is_empty():
		e["x"] = destroyed
	var flags: Array = _flag_changes(run)
	if not flags.is_empty():
		e["fl"] = flags
	if run.light != null:
		var sources: Dictionary = run.light.grid.sources_packed()
		if sources != _last_sources:
			e["s"] = sources
			_last_sources = sources
	if run.air_doors != null and run.air_doors.diff_log.size() > _doors_seen:
		var doors: Array = []
		for i: int in range(_doors_seen, run.air_doors.diff_log.size()):
			var d: Dictionary = run.air_doors.diff_log[i]
			doors.append([str(d.get("door", "")), Variants.flag(d.get("open", false))])
		_doors_seen = run.air_doors.diff_log.size()
		e["d"] = doors
	var sounds: Array = _sounds(run)
	if not sounds.is_empty():
		e["n"] = sounds
	if run.defender != null and run.defender.decisions.size() > _decisions_seen:
		e["dr"] = _plain(run.defender.decisions.slice(_decisions_seen))
		_decisions_seen = run.defender.decisions.size()
	# MNR-16: every shot (shooter, origin, aim, what it hit, the outcome) for RSC-07's card.
	if run.revolver != null and run.revolver.shots.size() > _shots_seen:
		e["shot"] = _plain(run.revolver.shots.slice(_shots_seen))
		_shots_seen = run.revolver.shots.size()
	for pair: Array in [["v", _voice], ["g", _creature_log], ["lie", _lies], ["fall", _falls], ["death", _deaths]]:
		var list: Array = pair[1]
		if not list.is_empty():
			e[pair[0]] = list.duplicate()
			list.clear()
	return e


## Entity flags that changed this tick (no system reports them to the feed).
func _flag_changes(run: RunState) -> Array:
	var out: Array = []
	var m: Dictionary = run.registry.packed_mirror()
	var ids: PackedInt64Array = m["ids"]
	var flags: PackedInt32Array = m["flags"]
	if ids == _last_ids and flags == _last_flags:
		return out
	var before: Dictionary = {}
	for i: int in _last_ids.size():
		before[_last_ids[i]] = _last_flags[i]
	for i: int in ids.size():
		var was: int = before.get(ids[i], flags[i])
		if was != flags[i]:
			out.append([ids[i], flags[i]])
	_last_ids = ids
	_last_flags = flags
	return out


## Every real sound dispatched this tick (SND-02's true-world log): its type, origins, level, the
## entity that made it, and each player delivery (listener, remaining level, muffled).
func _sounds(run: RunState) -> Array:
	var out: Array = []
	if run.noise == null:
		return out
	var events: Array[NoiseSystem.Event] = run.noise.event_log
	var i: int = events.size() - 1
	while i >= 0 and events[i].id > _last_sound:
		i -= 1
	for k: int in range(i + 1, events.size()):
		var ev: NoiseSystem.Event = events[k]
		var heard: Array = []
		for raw: Variant in ev.deliveries:
			var d: Dictionary = Variants.dict(raw)
			heard.append([int(Variants.number(d.get("listener", -1))), float(Variants.number(d.get("remaining_np", 0.0))),
				int(Variants.number(d.get("closed_portals", 0))) > 0])
		out.append({"id": ev.id, "type": ev.type, "origins": ev.origins.duplicate(), "level_np": ev.level_np, "source": ev.source_entity,
			"voice_id": ev.voice_id, "duration_s": ev.duration_s, "to_players": ev.to_players, "heard": heard})
		_last_sound = ev.id
	return out


## The true light of each client's 30x17 frame round its miner (the true view's light).
func _record_light(run: RunState) -> void:
	if run.light == null or run.vision == null:
		return
	for session: Sessions.Session in _net.sessions.welcomed():
		var e: SimEntity = run.registry.get_entity(run.vision.watched_entity(session.slot))
		if e == null:
			continue
		var origin: Vector2i = e.tile() - Vector2i(floori(frame_size.x / 2.0), floori(frame_size.y / 2.0))
		var lines: Dictionary = _open_streams.get(session.slot, {"l": [], "r": []})
		var light: PackedByteArray = run.light.grid.light_bytes(Rect2i(origin, frame_size))
		Variants.array(lines["l"]).append([run.tick, origin, light])
		_open_bytes += light.size()
		if run.tick % maxi(1, roundi(1000.0 / tick_ms)) == 0:
			Variants.array(lines["r"]).append([run.tick, roundi(_rtt_ms(session.slot))])
		_open_streams[session.slot] = lines



## The clients with anything in a block: its light lines or frames still held.
func _slots_for(item: Array) -> Array[int]:
	var streams: Dictionary = item[3]
	var seen: Dictionary = {}
	for raw: Variant in streams.keys():
		seen[raw] = true
	for raw: Variant in _frames.keys():
		seen[raw] = true
	var out: Array[int] = []
	for raw: Variant in seen.keys():
		var slot: int = raw
		out.append(slot)
	out.sort()
	return out


## One part of the block being sealed, a tick at a time: the authoritative track, then each
## client's stream; with the last, the block joins the ring, the ring rolls, windows due copy
## themselves out, and the budget is checked.
func _seal_step() -> void:
	var item: Array = _sealing["item"]
	var start: int = item[0]
	var last: int = start + block_ticks - 1
	if _sealing["block"] == null:
		var key: Dictionary = item[1]
		var ticks: Array = item[2]
		var made: RecordBlock = RecordBlock.new()
		made.start = start
		made.ticks = block_ticks
		made.auth_key = RecordBlock.Part.pack(key)
		made.auth = RecordBlock.Part.pack(ticks)
		_sealing["block"] = made
		return
	var block: RecordBlock = _sealing["block"]
	var slots: Array[int] = _sealing["slots"]
	if not slots.is_empty():
		var slot: int = slots.pop_front()
		var frames: Array = _take_frames(slot, start, last)
		var streams: Dictionary = item[3]
		var lines: Dictionary = streams.get(slot, {"l": [], "r": []})
		_open_bytes -= Variants.array(lines["l"]).size() * frame_size.x * frame_size.y
		var key: Dictionary = _keyframe(slot, start)
		if not frames.is_empty() or not Variants.array(lines["l"]).is_empty():
			block.streams[slot] = {"key": RecordBlock.Part.pack(key),
				"frames": RecordBlock.Part.pack({"f": frames, "l": lines["l"], "r": lines["r"]})}
		if not slots.is_empty():
			return
	_sealing = {}
	ring.append(block)
	_ring_bytes += block.size()
	while not ring.is_empty() and ring[0].last() < last - ring_ticks + 1:
		_ring_bytes -= ring[0].size()
		ring.pop_front()
	_finish_windows(last)
	_enforce_budget()


## The frames sent in [first, last], oldest first, each [tick, bytes, received, arrival_ms,
## illusion numbers]. A frame still unacknowledged this long after it was sent is lost: the client
## never decoded it, or no acknowledgement can name it any more.
func _take_frames(slot: int, first: int, last: int) -> Array:
	var out: Array = []
	var per: Dictionary = _frames.get(slot, {})
	var ticks: Array[int] = []
	for raw: Variant in per.keys():
		var t: int = raw
		if t >= first and t <= last:
			ticks.append(t)
	ticks.sort()
	var lost: Dictionary = _sealed_lost.get(slot, {})
	for t: int in ticks:
		var f: Array = per[t]
		var bytes: PackedByteArray = f[0]
		var state: int = f[1]
		var arrival: int = f[2]
		out.append([t, bytes, 1 if state == 1 else 0, arrival, f[3]])
		if state != 1:
			lost[t] = true
		_open_bytes -= bytes.size()
		per.erase(t)
		Variants.dict(_unacked.get(slot, {})).erase(t)
	for raw: Variant in lost.keys():
		var t: int = raw
		if t < last - 2 * Tuning.i(&"net.ack_history_frames"):
			lost.erase(t)
	_sealed_lost[slot] = lost
	return out


## A block's keyframe for one client, taken as its frames leave: every view a frame in the block
## is a delta against that the client held before the block began (the first is the newest it
## held then, `held`). NET-04's encoder keeps each frame's resulting view while it may be a
## baseline; it is exactly what the client decodes (test_run_record_ring.gd), so nothing is decoded.
func _key_views(slot: int, at_tick: int, bytes: PackedByteArray) -> void:
	if bytes.size() < 7 or _run == null or _run.replication == null:
		return
	if _origin < 0:
		_origin = at_tick
	var age: int = bytes[5] | (bytes[6] << 8)
	var block: int = _block_of(at_tick)
	var keys: Dictionary = _keys.get(slot, {})
	if not keys.has(block):
		keys[block] = {"held": at_tick - age if age > 0 else -1, "views": {}}
		_keys[slot] = keys
	var base: int = at_tick - age
	if age == 0 or base >= block:
		return
	var views: Dictionary = Variants.dict(keys[block])["views"]
	if not views.has(base):
		var view: Dictionary = _run.replication.native.sent_view(slot, base)
		if view.is_empty():
			keyframe_misses += 1
		else:
			views[base] = view


## A slot's keyframe for a block being sealed.
func _keyframe(slot: int, start: int) -> Dictionary:
	var keys: Dictionary = _keys.get(slot, {})
	var key: Dictionary = keys.get(start, {"held": -1, "views": {}})
	keys.erase(start)
	return key


func _block_of(t: int) -> int:
	return _origin + floori((t - _origin) / float(block_ticks)) * block_ticks


func _pin(kind: RecordWindow.Kind, entity: int, cause: int, detail: Dictionary) -> void:
	if discarded or _run == null:
		return
	var w: RecordWindow = RecordWindow.new()
	w.id = _next_window
	_next_window += 1
	w.kind = kind
	w.entity = entity
	w.slot = _slot_of(_run, entity)
	w.cause_tick = cause
	w.start = maxi(0, cause - window_before_ticks)
	w.end = _run.tick + window_tail_ticks
	w.detail = detail.duplicate(true)
	w.facts = Variants.dict(fact_extractor.call(_run, w))
	windows.append(w)
	_pending_windows.append(w)
	Log.info("run record: pinned window %d (%s) for miner %d, ticks %d-%d" % [w.id, RecordWindow.kind_name(kind), entity, w.start, w.end])


func _finish_windows(sealed_last: int) -> void:
	var keep: Array[RecordWindow] = []
	for w: RecordWindow in _pending_windows:
		if w.end > sealed_last:
			keep.append(w)
			continue
		for b: RecordBlock in blocks_between(w.start, w.end):
			w.blocks.append(b.only(w.slot))
		w.sealed = true
		_windows_bytes += w.size()
	_pending_windows = keep


func _enforce_budget() -> void:
	var total: int = memory_bytes()
	if total <= budget_bytes:
		return
	for w: RecordWindow in windows:
		if total <= budget_bytes:
			return
		if not w.sealed or w.thinned:
			continue
		var freed: int = w.thin()
		total -= freed
		_windows_bytes -= freed
		var line: String = "run record: over %d bytes; thinned window %d (%s) keyframes to every %.0f s, freeing %d bytes" % [
			budget_bytes, w.id, RecordWindow.kind_name(w.kind), 2.0 * block_ticks * tick_ms / 1000.0, freed]
		thinning_log.append(line)
		Log.info(line)



func _rtt_ms(slot: int) -> float:
	if _net == null:
		return 0.0
	for session: Sessions.Session in _net.sessions.welcomed():
		if session.slot == slot:
			return _net.transport.stats(session.peer).rtt_ms
	return 0.0


func _slot_of(run: RunState, entity: int) -> int:
	if run.movement == null:
		return -1
	for slot: int in run.movement.miner_slots():
		if run.movement.miner(slot).entity_id == entity:
			return slot
	return -1


func _entity_of(run: RunState, slot: int) -> int:
	var m: MovementSystem.Miner = run.movement.miner(slot) if run.movement != null else null
	return m.entity_id if m != null else 0


## Plain values only: an object becomes its text, so nothing in the record holds a live reference.
static func _plain(value: Variant) -> Variant:
	if value is Dictionary:
		var out: Dictionary = {}
		var d: Dictionary = value
		for k: Variant in d.keys():
			out[_plain(k)] = _plain(d[k])
		return out
	if value is Array:
		var out_a: Array = []
		var a: Array = value
		for v: Variant in a:
			out_a.append(_plain(v))
		return out_a
	if value is Object:
		return str(value)
	return value
