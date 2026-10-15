class_name RockTaps
extends SimSystem
## SND-12 (stage MINERS, after the lamp signals): rock taps (Gameplay §6.6, §6.4). ActionRecord.Kind.
## TAP_ROCK knocks on the nearest wall face (rock, coal, brick or timber) within touch range in the
## facing half-plane (Proposed), at most one tap per voice.tap_min_interval_s. Not while carrying (a
## carrier can only shutter, talk and call out: §4.3), Grabbed or unconscious, with the free hand
## blocked, or during the Aside; a Caught miner may. Each tap is a rock_tap event (noise.rock_tap_np,
## 10 np) at the wall: the air carries it as any sound, and RockTapLines carries it through the rock
## to the teammates within voice.rock_tap_range_tiles it did not reach by air, from the wall nearest
## each in the tapper's direction (brick and doors stop it, Proposed). A tap reaching an eligible
## teammate (SND-09) makes the tapper heard. A miner's taps with gaps of voice.rhythm_gap_s or less
## form one rhythm (intervals in 50 ms steps): `rhythm_tapped` feeds CRT-10 and CRT-12. No record
## names the tapper. Server-only.

## CRT-10, CRT-12: a finished rhythm: the gaps between its taps (ms, 50 ms steps) and their events.
signal rhythm_tapped(miner: int, intervals: PackedInt32Array, event_ids: PackedInt64Array)

const WALLS: Array[int] = [WorldIds.TileMaterial.ROCK, WorldIds.TileMaterial.COAL, WorldIds.TileMaterial.BRICK,
	WorldIds.TileMaterial.TIMBER]

## Taps emitted, waiting for the Road Graph's air delivery: {event, tapper, slot, wall, tick}.
var pending: Array[Dictionary] = []
## Every tap, refused ones included: {tick, miner, refused, why, wall, event}.
var taps: Array[Dictionary] = []
## Every delivery through the rock: {tick, event, listener (slot), face}.
var rock_deliveries: Array[Dictionary] = []
## miner -> {ticks: [], events: []}, the rhythm under way.
var _rhythm: Dictionary = {}
## miner -> the tick of its last tap.
var _last: Dictionary = {}


func stage() -> int:
	return StageTable.Stage.MINERS


func order() -> int:
	return 38


func system_name() -> String:
	return "rock_taps"


func tick(run: RunState) -> void:
	_close_rhythms(run)
	if run.movement == null:
		return
	for slot: int in run.movement.miner_slots():
		var c: InputBuffer.Consumed = run.input_for(slot)
		if c == null:
			continue
		for a: ActionRecord in c.actions:
			if a.kind == ActionRecord.Kind.TAP_ROCK:
				tap(run, run.movement.miner(slot).entity_id, slot)


## Taps if allowed: the event id, or 0 (refused).
func tap(run: RunState, miner: int, slot: int) -> int:
	var row: Dictionary = {"tick": run.tick, "miner": miner, "refused": true, "why": "", "wall": Vector2i(-1, -1), "event": 0}
	taps.append(row)
	var why: String = refusal(run, miner, slot)
	var wall: Vector2i = wall_face(run, miner, slot) if why.is_empty() else Vector2i(-1, -1)
	if why.is_empty() and wall == Vector2i(-1, -1):
		why = "no wall in reach"
	if not why.is_empty():
		row["why"] = why
		return 0
	var id: int = run.noise.emit(NoiseTypes.Type.ROCK_TAP, wall, {"source": miner}) if run.noise != null else 0
	_last[miner] = run.tick
	row["refused"] = false
	row["wall"] = wall
	row["event"] = id
	pending.append({"event": id, "tapper": miner, "slot": slot, "wall": wall, "tick": run.tick})
	var r: Dictionary = _rhythm.get(miner, {"ticks": PackedInt64Array(), "events": PackedInt64Array()})
	var ticks: PackedInt64Array = r["ticks"]
	var events: PackedInt64Array = r["events"]
	ticks.append(run.tick)
	events.append(id)
	_rhythm[miner] = {"ticks": ticks, "events": events}
	return id


## Why `miner` may not tap now ("" if it may).
func refusal(run: RunState, miner: int, slot: int) -> String:
	if run.miner_state != null and run.miner_state.miner(miner) != null:
		var life: int = run.miner_state.life(miner)
		if life != MinerTransitions.Life.UPRIGHT and life != MinerTransitions.Life.CAUGHT:
			return "grabbed, unconscious or dead"
	if run.inventory != null:
		var h: HandsAndBelt = run.inventory.hands_of(miner)
		if h.two_handed or h.hooked or run.inventory.free_hand_blocked(miner, &"tap"):
			return "carrying or the free hand full"
	if run.voice != null and int(Variants.number(run.voice.route_of.get(slot, VoiceRoutes.Route.NORMAL))) == VoiceRoutes.Route.ASIDE:
		return "the Aside"
	var gap: int = ceili(Tuning.f(&"voice.tap_min_interval_s") * Tuning.f(&"net.tick_hz"))
	if _last.has(miner) and run.tick - int(Variants.number(_last[miner])) < gap:
		return "too soon"
	return ""


## The wall face tapped: the nearest wall tile (WALLS) within vision.touch_range_tiles of the
## miner (to its nearest point) in the facing half-plane; (-1, -1) if none.
func wall_face(run: RunState, miner: int, slot: int) -> Vector2i:
	if run.mine == null:
		return Vector2i(-1, -1)
	var me: SimEntity = run.registry.get_entity(miner)
	var u: PackedFloat64Array = LbDetMath.unit(float(run.movement.facing_of(slot)) / 65536.0)
	var facing: Vector2 = Vector2(u[0], u[1])
	var reach: float = Tuning.f(&"vision.touch_range_tiles")
	var here: Vector2i = me.tile()
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: float = INF
	for dy: int in range(-2, 3):
		for dx: int in range(-2, 3):
			var t: Vector2i = here + Vector2i(dx, dy)
			if not WALLS.has(run.mine.native.material_at(t)):
				continue
			var nearest: Vector2 = Vector2(clampf(me.position.x, t.x, t.x + 1.0), clampf(me.position.y, t.y, t.y + 1.0))
			var d: float = nearest.distance_to(me.position)
			if d > reach or facing.dot(Vector2(t) + Vector2(0.5, 0.5) - me.position) <= 0.0:
				continue
			if d < best_d - 1e-9:
				best_d = d
				best = t
	return best


## RockTapLines, after the Road Graph's dispatch: through the rock to the teammates the air missed,
## and the tapper heard if an eligible teammate got it.
func deliver_pending(run: RunState) -> void:
	if pending.is_empty() or run.noise == null:
		return
	var by_id: Dictionary = {}
	for i: int in range(run.noise.event_log.size() - 1, -1, -1):
		var e: NoiseSystem.Event = run.noise.event_log[i]
		if e.tick < run.tick - 2:
			break
		by_id[e.id] = e
	var still: Array[Dictionary] = []
	for p: Dictionary in pending:
		var e: NoiseSystem.Event = by_id.get(int(Variants.number(p["event"])), null)
		if e == null:
			still.append(p)
			continue
		_deliver_through_rock(run, p, e)
	pending = still


func _deliver_through_rock(run: RunState, p: Dictionary, e: NoiseSystem.Event) -> void:
	var tapper_slot: int = int(Variants.number(p["slot"]))
	var tapper: SimEntity = run.registry.get_entity(int(Variants.number(p["tapper"])))
	var by_air: Dictionary = {}
	for raw: Variant in e.deliveries:
		by_air[int(Variants.number(Variants.dict(raw)["listener"]))] = true
	var reached: bool = false
	for raw: Variant in by_air.keys():
		var slot: int = int(Variants.number(raw))
		if slot != tapper_slot and run.heard != null and run.heard.eligible_listener(slot):
			reached = true
	if tapper != null and run.movement != null:
		var from: Vector2i = tapper.tile()
		for slot: int in run.movement.miner_slots():
			if slot == tapper_slot or by_air.has(slot) or _out_cold(run, slot):
				continue
			var m: MovementSystem.Miner = run.movement.miner(slot)
			var at: Vector2i = Vector2i(floori(m.state.x), floori(m.state.y))
			if Vector2(from).distance_to(Vector2(at)) > Tuning.f(&"voice.rock_tap_range_tiles") + 1e-6:
				continue
			var line: Dictionary = run.road_graph.graph.rock_line(from, at) if run.road_graph != null else {}
			if line.is_empty() or Variants.flag(line.get("brick", false)) or Variants.flag(line.get("door", false)) \
					or not Variants.flag(line.get("has_face", false)):
				continue
			var face: Vector2i = line.get("listener_face", at)
			var r: AudioRecord = AudioRecord.new()
			r.type = NoiseTypes.Type.ROCK_TAP
			r.start_tick = e.tick
			r.apparent = Vector2(face) + Vector2(0.5, 0.5)
			r.level_np = e.level_np
			r.remaining_np = maxf(0.0, e.level_np - float(Variants.number(line.get("distance", 0.0))) * Tuning.f(&"noise.air_cost_per_tile"))
			r.duration_s = e.duration_s
			if run.audio != null and run.audio.deliver(slot, r, e.id, float(Variants.number(line.get("distance", 0.0))), -1):
				rock_deliveries.append({"tick": run.tick, "event": e.id, "listener": slot, "face": face})
				if run.heard != null and run.heard.eligible_listener(slot):
					reached = true
	if reached and run.heard != null:
		run.heard.mark_heard(tapper_slot, &"tap")


func _out_cold(run: RunState, slot: int) -> bool:
	if run.miner_state == null:
		return false
	var life: int = run.miner_state.life(run.movement.miner(slot).entity_id)
	return life == MinerTransitions.Life.UNCONSCIOUS or life == MinerTransitions.Life.DEAD


## Ends every rhythm whose last tap is more than voice.rhythm_gap_s ago.
func _close_rhythms(run: RunState) -> void:
	var gap: int = roundi(Tuning.f(&"voice.rhythm_gap_s") * Tuning.f(&"net.tick_hz"))
	var ms_per_tick: float = 1000.0 / Tuning.f(&"net.tick_hz")
	var ids: Array = _rhythm.keys()
	ids.sort()
	for raw: Variant in ids:
		var r: Dictionary = _rhythm[raw]
		var ticks: PackedInt64Array = r["ticks"]
		if run.tick - ticks[ticks.size() - 1] <= gap:
			continue
		var intervals: PackedInt32Array = PackedInt32Array()
		for i: int in range(1, ticks.size()):
			intervals.append(roundi((ticks[i] - ticks[i - 1]) * ms_per_tick / 50.0) * 50)
		_rhythm.erase(raw)
		rhythm_tapped.emit(int(Variants.number(raw)), intervals, r["events"])


func write_state(writer: SimStateWriter) -> void:
	writer.put_i64(pending.size())
	writer.put_i64(_rhythm.size())
