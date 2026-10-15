class_name DarkSystem
extends SimSystem
## RSC-04 (stage FALLS, after RSC-01's falls): the Dark (Gameplay §11.8). A fallen player gets their
## own view of the moments before the fall, once the run record has sealed it (NET-07's window,
## REPLAY), then black: VIS-03's blinding (RSC-01's) and game sound round the body only, muffled
## (the "dark" mask: rescue.unconscious_gain_db, MUFFLED). They talk freely with every other fallen
## or dead player on the dream channel ("dream": no noise, never to the living).
##
## Every rescue.coming_round_interval_s (drawn from rescue.coming_round, measured from the last
## window's end, Proposed) an unconscious miner comes round for rescue.coming_round_window_s: the
## crawl at rescue.crawl_speed (never carried or Caught, Proposed), their own cone within
## rescue.window_sight_tiles by the normal rules, and their voice to the living as a muffled whisper
## (SND-07's COMING_ROUND route, real 6 np events) besides the dream channel; the callout wheel
## offers 'Help!' and a moan (SND-11). At its end the voice is cut and the view black again.
##
## Any fallen or dead player may watch a conscious teammate's own stream rescue.watch_delay_s late
## (WATCH: the frames as sent to them, illusions and all, no voice, black while they read a
## close-up); when the watched miner falls their screen plays out to the fall, goes dark, and the
## watch ends. The dead keep the dream channel and watching only, and hear no game sound.

const DREAM: String = "dream"
const OWNER: StringName = &"dark"
## Frames a replay message carries.
const REPLAY_CHUNK: int = 60


class Fallen:
	extends RefCounted
	var entity: int = 0
	var slot: int = -1
	var fell_tick: int = 0
	var fall_id: int = 0
	var dead: bool = false
	var next_window: int = 0
	var window_end: int = -1
	var window_from: Vector2 = Vector2.ZERO
	var window_spoke: bool = false
	var window_help: bool = false
	var replay_sent: bool = false
	var watching: int = -1
	var watched_to: int = -1
	## On the dream channel: from the end of the fall scream (SND-15 hands the route over as CUT).
	var in_dream: bool = false
	## The player dropped during the spell (the retention metric's "stayed to the end").
	var left: bool = false
	var rng: LbRng = null


## entity -> Fallen
var fallen: Dictionary = {}
## Every window, for tests and telemetry: {entity, open, close}.
var windows_log: Array[Dictionary] = []
## Messages sent this tick, [slot, type, bytes] (NET-08's audit and the tests read them).
var sent: Array[Array] = []
var _net: ServerNet = null
var _run: RunState = null
## slot -> the peer last sent to: a rejoined client (NET-11) has no baselines, so its watch restarts.
var _peers: Dictionary = {}


func stage() -> int:
	return StageTable.Stage.FALLS


func order() -> int:
	return 45


func system_name() -> String:
	return "dark"


func bind(run: RunState, net: ServerNet) -> void:
	_run = run
	_net = net
	if run.falls != null:
		run.falls.fell.connect(_on_fell)
	if run.miner_state != null:
		run.miner_state.state_changed.connect(_on_state_changed)
	if run.audio != null:
		run.audio.register_mask("dark", mask)
	run.phase_changed.connect(func(phase: RunState.Phase) -> void:
		if phase == RunState.Phase.ENDED:
			for raw: Variant in fallen.values():
				var f: Fallen = raw
				if not f.dead:
					_log_spell(f, "run_end"))
	if run.voice != null:
		run.voice.band_heard.connect(func(slot: int, _band: int) -> void:
			var f: Fallen = of_slot(slot)
			if f != null and f.window_end >= 0:
				f.window_spoke = true)


func of_slot(slot: int) -> Fallen:
	for raw: Variant in fallen.values():
		var f: Fallen = raw
		if f.slot == slot:
			return f
	return null


func in_window(entity: int) -> bool:
	var f: Fallen = fallen.get(entity, null)
	return f != null and f.window_end >= 0


## SND-03's mask: the unconscious hear game sound round their body, muffled and low; the dead none.
func mask(run: RunState, slot: int, _record: AudioRecord) -> Variant:
	var f: Fallen = of_slot(slot)
	if f == null:
		return {}
	if f.dead:
		return null
	if run.miner_state != null and run.miner_state.life(f.entity) != MinerTransitions.Life.UNCONSCIOUS:
		return {}
	return {"gain_db": roundi(Tuning.f(&"rescue.unconscious_gain_db")), "flags": AudioRecord.MUFFLED}


func tick(run: RunState) -> void:
	_run = run
	sent.clear()
	var ids: Array = fallen.keys()
	ids.sort()
	for raw: Variant in ids:
		var f: Fallen = fallen[raw]
		f.slot = _slot_of(run, f.entity)
		_on_rejoin(f)
		_join_dream(run, f)
		_watch_asks(run, f)
		if not f.dead:
			if f.window_end < 0 and run.tick >= f.next_window:
				_open_window(run, f)
			elif f.window_end >= 0 and run.tick >= f.window_end:
				_close_window(run, f)
			if f.window_end >= 0:
				_hold_crawl(run, f)
		if not f.replay_sent:
			_send_replay(run, f)
		if f.watching >= 0:
			_relay(run, f)


## Coming round: the crawl, the own cone within 4 tiles, the whisper to the living.
func _open_window(run: RunState, f: Fallen) -> void:
	f.window_end = run.tick + maxi(1, roundi(Tuning.f(&"rescue.coming_round_window_s") * Tuning.f(&"net.tick_hz")))
	f.window_spoke = false
	f.window_help = false
	var e: SimEntity = run.registry.get_entity(f.entity)
	f.window_from = e.position if e != null else Vector2.ZERO
	run.miner_state.set_crawl_window(f.entity, true)
	if f.slot >= 0:
		if run.vision != null:
			run.vision.set_blind(f.slot, &"fallen", false)
			run.vision.native.set_radius_clamp(f.slot, Tuning.f(&"rescue.window_sight_tiles"))
		if run.voice != null:
			run.voice.set_route(f.slot, VoiceRoutes.Route.COMING_ROUND)
	_hold_crawl(run, f)
	windows_log.append({"entity": f.entity, "open": run.tick, "close": f.window_end})


func _close_window(run: RunState, f: Fallen) -> void:
	_end_window(run, f)
	f.next_window = run.tick + _gap(f)
	var e: SimEntity = run.registry.get_entity(f.entity)
	var crawled: float = e.position.distance_to(f.window_from) if e != null else 0.0
	Log.info("telemetry window_use spoke=%s help=%s crawl_tiles=%.2f" % [f.window_spoke, f.window_help, crawled])


func _end_window(run: RunState, f: Fallen) -> void:
	if f.window_end < 0:
		return
	f.window_end = -1
	if run.miner_state != null:
		run.miner_state.set_crawl_window(f.entity, false)
	if f.slot >= 0:
		if run.vision != null:
			run.vision.native.set_radius_clamp(f.slot, 0.0)
			run.vision.set_blind(f.slot, &"fallen", run.miner_state != null and run.miner_state.life(f.entity) >= MinerTransitions.Life.UNCONSCIOUS)
		if run.voice != null and run.miner_state != null and run.miner_state.life(f.entity) == MinerTransitions.Life.UNCONSCIOUS:
			run.voice.set_route(f.slot, VoiceRoutes.Route.CUT)
		if run.movement != null:
			run.movement.set_constraint(f.slot, OWNER, null)


## The crawl: rescue.crawl_speed, and none while Caught (Proposed; a carried body has its own lock).
func _hold_crawl(run: RunState, f: Fallen) -> void:
	if f.slot < 0 or run.movement == null:
		return
	var c: MinerMotion.Constraints = MinerMotion.Constraints.new()
	c.fixed_speed = Tuning.f(&"rescue.crawl_speed")
	c.run_allowed = false
	c.movement_off = run.holds != null and run.holds.caught_in(f.entity) != null
	run.movement.set_constraint(f.slot, OWNER, c)


## Watching: ActionRecord.Kind.WATCH (1 the next conscious teammate, 2 the one before, 0 stop).
func _watch_asks(run: RunState, f: Fallen) -> void:
	var c: InputBuffer.Consumed = run.input_for(f.slot) if f.slot >= 0 else null
	if c == null:
		return
	for a: ActionRecord in c.actions:
		if a.kind != ActionRecord.Kind.WATCH:
			continue
		if a.arg == 0:
			_stop_watching(f)
			continue
		var choices: Array[int] = watchable(run, f.slot)
		if choices.is_empty():
			continue
		var at: int = choices.find(f.watching)
		var step: int = 1 if a.arg == 1 else -1
		var next: int = choices[posmod(at + step, choices.size())] if at >= 0 else (choices[0] if step > 0 else choices[choices.size() - 1])
		if next != f.watching:
			_stop_watching(f)
			f.watching = next
			f.watched_to = -1


## The conscious human teammates one may watch, by slot (Proposed until MOD-03 seats lamp numbers).
func watchable(run: RunState, watcher: int) -> Array[int]:
	var out: Array[int] = []
	if run.movement == null or run.miner_state == null:
		return out
	for slot: int in run.movement.miner_slots():
		if slot == watcher:
			continue
		var entity: int = run.movement.miner(slot).entity_id
		var life: int = run.miner_state.life(entity)
		var hand: bool = run.crew != null and Variants.flag(run.crew.is_hand_driven.call(entity))
		if not hand and life <= MinerTransitions.Life.GRABBED:
			out.append(slot)
	return out


func _stop_watching(f: Fallen) -> void:
	if f.watching >= 0 and f.slot >= 0:
		_send(f.slot, Protocol.Msg.WATCH, DarkMessages.watch(false, {}, [], true))
	f.watching = -1
	f.watched_to = -1


## The watched stream, as sent to the watched miner, rescue.watch_delay_s late.
func _relay(run: RunState, f: Fallen) -> void:
	if run.record == null or f.slot < 0:
		return
	var at: int = run.tick - 1 - roundi(Tuning.f(&"rescue.watch_delay_s") * Tuning.f(&"net.tick_hz"))
	if at < 0 or at > run.record.sealed_to():
		return
	var target_fall: int = -1
	var target_entity: int = run.movement.miner(f.watching).entity_id if run.movement.miner(f.watching) != null else 0
	var tf: Fallen = fallen.get(target_entity, null)
	if tf != null:
		target_fall = tf.fell_tick
	var until: int = at
	var ends: bool = false
	if target_fall >= 0 and at >= target_fall + roundi(Tuning.f(&"net.record_tail_s") * Tuning.f(&"net.tick_hz")):
		until = target_fall + roundi(Tuning.f(&"net.record_tail_s") * Tuning.f(&"net.tick_hz"))
		ends = true  # the fall has played out, late, and gone dark
	var reset: bool = f.watched_to < 0
	var got: Dictionary = RecordReaders.frames_for_relay(run.record, f.watching, f.watched_to, until)
	var frames: Array = got["frames"]
	if reset or not frames.is_empty():
		var views: Dictionary = got["views"] if reset else {}
		_send(f.slot, Protocol.Msg.WATCH, DarkMessages.watch(reset, views, frames))
	f.watched_to = until
	if ends:
		_stop_watching(f)


## The victim's own view of the moments before the fall, once the record has sealed it.
func _send_replay(run: RunState, f: Fallen) -> void:
	if run.record == null or f.slot < 0:
		f.replay_sent = run.record == null
		return
	var w: RecordWindow = null
	for rw: RecordWindow in run.record.windows:
		if rw.kind == RecordWindow.Kind.FALL and rw.entity == f.entity and int(Variants.number(rw.detail.get("fall_id", -1))) == f.fall_id:
			w = rw
	if w == null or not w.sealed:
		return
	f.replay_sent = true
	var views: Dictionary = {}
	var frames: Array = []
	for b: RecordBlock in w.blocks:
		if views.is_empty():
			views = Variants.dict(b.stream_keyframe(w.slot).get("views", {}))
		for raw: Variant in Variants.array(b.stream_ticks(w.slot).get("f", [])):
			var fr: Array = raw
			var t: int = fr[0]
			var received: int = fr[2]
			if received == 1 and t <= f.fell_tick:
				frames.append([t, fr[1]])
	var parts: int = maxi(1, ceili(frames.size() / float(REPLAY_CHUNK)))
	for i: int in parts:
		_send(f.slot, Protocol.Msg.REPLAY, DarkMessages.replay(i, parts, views if i == 0 else {}, frames.slice(i * REPLAY_CHUNK, (i + 1) * REPLAY_CHUNK)))


func _on_fell(record: Dictionary) -> void:
	var entity: int = int(Variants.number(record.get("miner_id", 0)))
	if _run == null or fallen.has(entity):
		return
	var f: Fallen = Fallen.new()
	f.entity = entity
	f.slot = _slot_of(_run, entity)
	f.fell_tick = int(Variants.number(record.get("tick", _run.tick)))
	f.fall_id = int(Variants.number(record.get("fall_id", 0)))
	f.rng = _run.stream(HashDomain.RESCUE_COMING_ROUND, PackedInt64Array([entity]))
	f.next_window = _run.tick + _gap(f)
	f.replay_sent = Variants.flag(record.get("is_hand", false)) or f.slot < 0
	fallen[entity] = f


func _on_state_changed(entity: int, old: int, new: int, _cause: String) -> void:
	var f: Fallen = fallen.get(entity, null)
	if f == null:
		if new == MinerTransitions.Life.DEAD and _run != null:
			# Killed outright: the dead keep the dream channel and watching.
			f = Fallen.new()
			f.entity = entity
			f.slot = _slot_of(_run, entity)
			f.fell_tick = _run.tick
			f.dead = true
			f.replay_sent = true
			fallen[entity] = f
		return
	if new == MinerTransitions.Life.DEAD:
		_end_window(_run, f)
		f.dead = true
		_log_spell(f, "dead")
	elif old == MinerTransitions.Life.UNCONSCIOUS and new != MinerTransitions.Life.UNCONSCIOUS:
		_end_window(_run, f)
		if f.slot >= 0:
			if _run.voice != null and f.in_dream:
				_run.voice.channel_leave(DREAM, f.slot)
			if _run.vision != null:
				_run.vision.native.set_radius_clamp(f.slot, 0.0)
		_stop_watching(f)
		fallen.erase(entity)
		_log_spell(f, "revived")


## GDD §15.12's unconscious_spell, for the 80% retention target (§C.8).
func _log_spell(f: Fallen, outcome: String) -> void:
	Log.info("telemetry unconscious_spell duration_s=%.1f stayed_to_end=%s outcome=%s"
		% [(_run.tick - f.fell_tick) / Tuning.f(&"net.tick_hz"), not f.left, outcome])


## The dream channel replaces proximity whatever the route, so it waits for the fall scream to end.
func _join_dream(run: RunState, f: Fallen) -> void:
	if f.in_dream or f.slot < 0 or run.voice == null:
		return
	var route: int = int(Variants.number(run.voice.route_of.get(f.slot, VoiceRoutes.Route.NORMAL)))
	if route == VoiceRoutes.Route.FALL_SCREAM or route == VoiceRoutes.Route.FALL_MUFFLED:
		return
	f.in_dream = true
	run.voice.channel_join(DREAM, f.slot)


func _gap(f: Fallen) -> int:
	var hz: float = Tuning.f(&"net.tick_hz")
	var span: Vector2 = Tuning.range_f(&"rescue.coming_round_interval_s")
	return f.rng.range(roundi(span.x * hz), roundi(span.y * hz))


## A rejoining player returns to the Dark (§13.11): blinding, the dream channel and the window
## schedule are the slot's and stay; the watch starts again from a keyframe for the new client.
func _on_rejoin(f: Fallen) -> void:
	if _net == null or f.slot < 0:
		return
	var peer: int = -1
	for session: Sessions.Session in _net.sessions.welcomed():
		if session.slot == f.slot:
			peer = session.peer
	if peer != int(Variants.number(_peers.get(f.slot, peer))):
		f.watched_to = -1
	if _net.dropped_slots.has(f.slot):
		f.left = true
	_peers[f.slot] = peer


func _send(slot: int, type: Protocol.Msg, bytes: PackedByteArray) -> void:
	sent.append([slot, type, bytes])
	if _net == null:
		return
	for session: Sessions.Session in _net.sessions.welcomed():
		if session.slot == slot:
			_net.transport.send(session.peer, Lane.Id.CONTROL, Protocol.frame(type, bytes))


func _slot_of(run: RunState, entity: int) -> int:
	if run.movement == null:
		return -1
	for slot: int in run.movement.miner_slots():
		if run.movement.miner(slot).entity_id == entity:
			return slot
	return -1


func write_state(writer: SimStateWriter) -> void:
	var ids: Array = fallen.keys()
	ids.sort()
	writer.put_i64(ids.size())
	for raw: Variant in ids:
		var f: Fallen = fallen[raw]
		writer.put_i64(f.entity)
		writer.put_i64(f.fell_tick)
		writer.put_bool(f.dead)
		writer.put_i64(f.next_window)
		writer.put_i64(f.window_end)
		writer.put_i64(f.watching)
