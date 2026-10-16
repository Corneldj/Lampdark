class_name FallSystem
extends SimSystem
## RSC-01 (stage FALLS, after RSC-03's holds): every fall to Unconscious, through one call.
## fall_unconscious(miner, cause, ctx) refuses a miner already down, settles the lamp by the cause
## (LampDisposition) and asks MNR-03 for the transition, which applies at the tick's end. When
## MNR-03's state_changed reports Unconscious, by this call or another route (a pin running out
## through end_grab, a drag through RSC-03), the fall is journalled at once and `fell` is
## emitted just after MNR-03's flush, the same tick, with the full record; the fallen player's view goes black (VIS-03's blinding; RSC-04's Dark replaces it);
## and the body is tracked here (BodyState). Nothing here ends Unconscious: no timer runs on the
## fallen. Server-only: the record, the body state and the journal never reach a client.

signal fell(record: Dictionary)

## Emits the tick's falls just after MNR-03's flush (stage RECORD), so `fell` follows every
## state_changed listener in the same tick.
class Emit:
	extends SimSystem
	var owner: FallSystem

	func _init(of: FallSystem) -> void:
		owner = of

	func stage() -> int:
		return StageTable.Stage.RECORD

	func order() -> int:
		return 5

	func system_name() -> String:
		return "falls_emit"

	func tick(_run: RunState) -> void:
		owner.emit_fallen()


## entity -> BodyState, for every miner lying unconscious or dead.
var bodies: Dictionary = {}
## NET-09's journal stand-in: every fall record, written in the tick of the fall.
var journal: Array[Dictionary] = []
## miner -> {cause, ctx, lamp_outcome} for falls asked for this tick, awaiting MNR-03's flush.
var _pending: Dictionary = {}
## miner -> the tick it was last seen not alone (AloneRules, sampled each second), for the
## telemetry's alone_s.
var _not_alone_at: Dictionary = {}
var _next_fall_id: int = 1
## Records of this tick's falls, emitted by Emit after MNR-03's flush.
var _to_emit: Array[Dictionary] = []
var _run: RunState = null
## GEN-13: entity -> [cell, payload] of its body record.
var _body_records: Dictionary = {}


func stage() -> int:
	return StageTable.Stage.FALLS


func order() -> int:
	return 20


func system_name() -> String:
	return "falls"


func bind(run: RunState) -> void:
	_run = run
	if run.miner_state != null:
		run.miner_state.state_changed.connect(_on_state_changed)
	run.add_system(Emit.new(self))
	if run.diff_log != null:
		run.diff_log.register(DiffLog.Kind.BODY, _replay_body)
		run.diff_log.on_sync(sync_body_records)
		run.diff_log.on_refresh(sync_body_records)


## GEN-13: every body at rest (not carried or dragged) has a record in its cell: where it lies,
## on a table, dead, kept in the lair. A body moved gets its record moved; one that rises loses it.
func sync_body_records(run: RunState) -> void:
	var seen: Dictionary = {}
	for entity: int in _sorted_bodies():
		var b: BodyState = bodies[entity]
		seen[entity] = true
		if b.carried_by != 0 or b.dragged_by != 0 or not run.registry.has(entity):
			continue
		var e: SimEntity = run.registry.get_entity(entity)
		var cell: Vector2i = WorldCoords.cell_of(e.tile())
		var p: Dictionary = {"x": e.position.x, "y": e.position.y, "table": b.on_table, "dead": b.dead, "kept": b.kept_in_lair}
		var was: Array = _body_records.get(entity, [])
		if not was.is_empty() and was[0] == cell and was[1] == p:
			continue
		if not was.is_empty():
			var old: Vector2i = was[0]
			if old != cell:
				run.diff_log.erase(old, DiffLog.Kind.BODY, "m%d" % entity)
		run.diff_log.record(cell, DiffLog.Kind.BODY, "m%d" % entity, p)
		_body_records[entity] = [cell, p]
	for raw: Variant in _body_records.keys():
		if not seen.has(raw):
			var gone: Array = _body_records[raw]
			var gone_cell: Vector2i = gone[0]
			run.diff_log.erase(gone_cell, DiffLog.Kind.BODY, "m%d" % int(Variants.number(raw)))
			_body_records.erase(raw)


## A body's record put back: it lies where recorded (a resume, or a cell committed again).
func _replay_body(run: RunState, cell: Vector2i, key: String, p: Dictionary, _t: int) -> void:
	var entity: int = int(key.trim_prefix("m"))
	if not run.registry.has(entity):
		return
	var at: Vector2 = Vector2(Variants.number(p["x"]), Variants.number(p["y"]))
	var b: BodyState = body_of(entity)
	if b != null and (b.carried_by != 0 or b.dragged_by != 0):
		return
	if run.registry.get_entity(entity).position != at:
		if run.movement != null:
			run.movement.place(run, entity, at)
		else:
			run.registry.move(entity, at)
	_body_records[entity] = [cell, p]


## Emits `fell` for this tick's falls (Emit calls it, after MNR-03's flush).
func emit_fallen() -> void:
	var records: Array[Dictionary] = _to_emit
	_to_emit = []
	for r: Dictionary in records:
		fell.emit(r)


## The one entry point for a fall (CRT-04, CRT-06, CRT-09, CRT-14, HAZ-03 to HAZ-05, MNR-16).
## ctx may carry: moth_takes_lamp (the Moth's entity), grab_point (Vector2i), creature, igniter,
## shooter, grab_id, trap_id, tell_logged. Returns false if the miner is already down.
func fall_unconscious(run: RunState, miner: int, cause: FallCause.Cause, ctx: Dictionary = {}) -> bool:
	if run.miner_state == null or run.miner_state.miner(miner) == null:
		return false
	var life: int = run.miner_state.life(miner)
	if life == MinerTransitions.Life.UNCONSCIOUS or life == MinerTransitions.Life.DEAD or _pending.has(miner):
		return false
	var outcome: String = LampDisposition.resolve(run, miner, cause, ctx)
	_pending[miner] = {"cause": cause, "ctx": ctx.duplicate(), "lamp_outcome": outcome}
	run.miner_state.fall_unconscious(miner, FallCause.name_of(cause), ctx)
	return true


func body_of(entity: int) -> BodyState:
	return bodies.get(entity, null)


## Bodies on the floor (not carried, not on a table, not in the lair) within `r` of `pos`
## (CRT-06's laying, CRT-15's collecting), ascending id.
func on_floor_within(run: RunState, pos: Vector2, r: float) -> Array[int]:
	var out: Array[int] = []
	for id: int in _sorted_bodies():
		var b: BodyState = bodies[id]
		var e: SimEntity = run.registry.get_entity(id)
		if e != null and b.on_floor and b.carried_by == 0 and not b.on_table and not b.kept_in_lair \
				and e.position.distance_to(pos) <= r:
			out.append(id)
	return out


## Of those, the ones lying unlit: below 0.30 on the light grid.
func lying_unlit_within(run: RunState, pos: Vector2, r: float) -> Array[int]:
	var out: Array[int] = []
	for id: int in on_floor_within(run, pos, r):
		if run.light == null or run.light.light_at(run.registry.get_entity(id).tile()) < 0.30:
			out.append(id)
	return out


## Taking an item from a body's belt (MNR-05's ring): rescue.take_item_s held in touch range; an
## early release takes nothing; refused if the taker's belt cannot take it whole.
func take_item_action(run: RunState, taker: int, body: int, slot: int) -> TimedAction:
	var a: TimedAction = TimedAction.make(taker, &"take_from_body", Tuning.f(&"rescue.take_item_s"), InputRecord.HOLD_INTERACT)
	a.target_entity = body
	a.reach = Tuning.f(&"vision.touch_range_tiles")
	var inv: InventorySystem = run.inventory
	a.valid = func() -> bool:
		if not bodies.has(body):
			return false
		var item: Item = inv.hands_of(body).slots[slot] if slot < inv.hands_of(body).slots.size() else null
		return item != null and inv.hands_of(taker).fits(item)
	a.effect = func() -> void:
		var item: Item = inv.take(run, body, slot)
		inv.give(run, taker, item)
	return a


## Lifting a body into a fireman's carry (2 s, movement.carry_lift_time): refused while a trap
## holds it or someone carries it, or if the lifter's hands are not free. The carry itself, its
## pace and setting down are MNR-13's.
func lift_action(run: RunState, lifter: int, body: int) -> TimedAction:
	if run.carry != null:
		return run.carry.lift_action(run, lifter, body)
	var a: TimedAction = TimedAction.make(lifter, &"lift_body", Tuning.f(&"movement.carry_lift_time"), InputRecord.HOLD_INTERACT)
	a.target_entity = body
	a.reach = Tuning.f(&"vision.touch_range_tiles")
	a.valid = func() -> bool:
		var b: BodyState = bodies.get(body, null)
		return b != null and not b.held_by_trap and b.carried_by == 0 and b.dragged_by == 0 \
			and run.inventory.hands_of(lifter).free_hand == null
	a.effect = func() -> void:
		if run.inventory.begin_two_handed(run, lifter):
			var b: BodyState = bodies[body]
			b.carried_by = lifter
			b.on_floor = false
	return a


## VIS-07's feel caption for a body, or "" if the entity is not one.
func feel_caption(entity: int) -> String:
	var b: BodyState = bodies.get(entity, null)
	return b.feel_caption() if b != null else ""


func tick(run: RunState) -> void:
	_run = run
	# The telemetry's alone_s needs only a second's resolution: sampled once a second.
	if run.movement != null and run.tick % roundi(Tuning.f(&"net.tick_hz")) == 0:
		for slot: int in run.movement.miner_slots():
			var m: int = run.movement.miner(slot).entity_id
			if not _not_alone_at.has(m) or not AloneRules.is_alone(run, m):
				_not_alone_at[m] = run.tick
	for id: int in _sorted_bodies():
		var b: BodyState = bodies[id]
		var ms: MinerStateSystem = run.miner_state
		var held: bool = ms != null and ms.miner(id) != null and not ms.miner(id).holder.is_empty()
		b.held_by_trap = held
		var g: GrabHold = run.holds.grab_of(id) if run.holds != null else null
		b.dragged_by = g.creature if g != null and g.kind == GrabHold.Kind.STYTHE_DRAG else 0
		if b.carried_by != 0:
			var carrier: SimEntity = run.registry.get_entity(b.carried_by)
			if carrier != null:
				run.registry.move(id, carrier.position)


func _on_state_changed(entity: int, old: int, new: int, cause: String) -> void:
	if new == MinerTransitions.Life.UNCONSCIOUS:
		_on_fell(entity, cause)
	elif new == MinerTransitions.Life.DEAD:
		var b: BodyState = bodies.get(entity, null)
		if b == null:
			b = _new_body(entity)
		b.dead = true
		_blind(entity, true)
	elif old == MinerTransitions.Life.UNCONSCIOUS:
		# Revived (RSC-02, RSC-09): up again, seeing again.
		bodies.erase(entity)
		_blind(entity, false)


func _on_fell(entity: int, state_cause: String) -> void:
	var run: RunState = _run
	var pending: Dictionary = _pending.get(entity, {})
	_pending.erase(entity)
	var cause: int = int(Variants.number(pending.get("cause", FallCause.from_state_cause(state_cause))))
	var ctx: Dictionary = Variants.dict(pending.get("ctx", {}))
	var b: BodyState = _new_body(entity)
	b.fall_id = _next_fall_id
	_next_fall_id += 1
	# A carrier felled drops whatever body they carry where they stand (§11.4): MNR-13's carry
	# does it when installed; this stand-in only without it.
	for id: int in ([] as Array[int]) if run.carry != null else _sorted_bodies():
		var carried: BodyState = bodies[id]
		if carried.carried_by == entity:
			carried.carried_by = 0
			carried.on_floor = true
			if run.inventory != null:
				run.inventory.end_two_handed(entity)
	var is_hand: bool = run.crew != null and Variants.flag(run.crew.is_hand_driven.call(entity))
	var scream: int = FallCause.Scream.FULL
	if is_hand or cause == FallCause.Cause.FRIENDLY_HIT or cause == FallCause.Cause.SHOT_DEAD:
		scream = FallCause.Scream.NONE
	elif cause == FallCause.Cause.DRAG:
		scream = FallCause.Scream.MUFFLED_WHISPER
	var e: SimEntity = run.registry.get_entity(entity)
	var record: Dictionary = {"fall_id": b.fall_id, "miner_id": entity, "is_hand": is_hand, "cause": cause,
		"cause_name": FallCause.name_of(cause) if cause >= 0 else state_cause, "tick": run.tick,
		"tile": e.tile() if e != null else Vector2i.ZERO, "ring": Depth.ring_for_miner(run, entity) if e != null else 0,
		"lamp_outcome": str(pending.get("lamp_outcome", "as_left")), "scream_mode": scream}
	for key: String in ["creature", "igniter", "shooter", "grab_id", "trap_id"]:
		if ctx.has(key):
			record[key] = ctx[key]
	journal.append(record)
	_blind(entity, true)
	var alone_s: float = (run.tick - int(Variants.number(_not_alone_at.get(entity, run.tick)))) / Tuning.f(&"net.tick_hz")
	Log.info("telemetry fall cause=%s ring=%d run_time=%.1f tell_logged=%s unheard_s=-1 alone_s=%.1f is_hand=%s" % [
		record["cause_name"], int(Variants.number(record["ring"])), run.tick / Tuning.f(&"net.tick_hz"),
		Variants.flag(ctx.get("tell_logged", false)), alone_s, is_hand])
	_to_emit.append(record)


## NET-09: the body of `entity`, made if it has none (a journaled fall put back on a resume).
func ensure_body(entity: int) -> BodyState:
	return body_of(entity) if body_of(entity) != null else _new_body(entity)


func _new_body(entity: int) -> BodyState:
	var b: BodyState = BodyState.new()
	b.entity = entity
	bodies[entity] = b
	return b


## M1: the fallen see nothing (VIS-03's seen set empties, so NET-04 sends only the own body).
func _blind(entity: int, on: bool) -> void:
	if _run == null or _run.vision == null or _run.movement == null:
		return
	for slot: int in _run.movement.miner_slots():
		if _run.movement.miner(slot).entity_id == entity:
			_run.vision.set_blind(slot, &"fallen", on)


func _sorted_bodies() -> Array[int]:
	var out: Array[int] = []
	for raw: Variant in bodies.keys():
		out.append(int(Variants.number(raw)))
	out.sort()
	return out


func write_state(writer: SimStateWriter) -> void:
	for id: int in _sorted_bodies():
		var b: BodyState = bodies[id]
		writer.put_i64(id)
		writer.put_bool(b.on_floor)
		writer.put_i64(b.carried_by)
		writer.put_i64(b.on_load)
		writer.put_bool(b.held_by_trap)
		writer.put_bool(b.dead)
	writer.put_i64(journal.size())


## NET-09: the bodies (a carry in progress is not kept: a resume finds the load set down) and the
## fall journal.
func save_state() -> Dictionary:
	var out: Dictionary = {}
	for e: int in _sorted_bodies():
		var b: BodyState = bodies[e]
		out[e] = StateDicts.pick(b, ["posture", "on_floor", "on_table", "on_load", "held_by_trap", "kept_in_lair", "dead", "fall_id"])
	return {"bodies": out, "journal": journal.duplicate(true), "next_fall_id": _next_fall_id}


func load_state(_r: RunState, state: Dictionary) -> void:
	var saved: Dictionary = Variants.dict(state.get("bodies", {}))
	for raw: Variant in saved.keys():
		var b: BodyState = _new_body(int(Variants.number(raw)))
		StateDicts.put(b, Variants.dict(saved[raw]))
		b.carried_by = 0
		b.dragged_by = 0
		if not b.on_table and b.on_load == 0:
			b.on_floor = true
	journal.clear()
	for r: Variant in Variants.array(state.get("journal", [])):
		journal.append(Variants.dict(r))
	_next_fall_id = int(Variants.number(state.get("next_fall_id", 1)))
