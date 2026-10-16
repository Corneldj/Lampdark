class_name FiremanCarry
extends SimSystem
## MNR-13 (stage MINERS, before the inventory): the fireman's carry (Gameplay §4.3, §11.4). One
## conscious miner lifts an unconscious or dead miner in 2 s of held interact (from the ring, or by
## interacting again after feeling them); the lamp hooks when the lift starts and unhooks if it is
## released early. Carrying is walk only at movement.carry_fireman_speed (a modifier on the walk, so
## a wound's x0.8 and sump mud still apply and the client predicts it from its speed factor), on
## heavy 12 np steps, with both hands full. Interact again sets the body down at once on the
## carrier's tile, or onto a free medbay table within touch range. A carrier who is smothered,
## grabbed or felled drops it where they stand that tick; NET-11 sets it down on a disconnect.
## Server-only; observers see the body over the carrier's shoulder on the carrier's identity record
## (InventorySystem.held_bits) and never as a token of its own.

signal carry_started(carrier: int, body: int)
signal carry_ended(carrier: int, body: int, reason: StringName)

const OWNER: StringName = &"fireman_carry"
## The carried body's own lock: no crawl (RSC-04) or any input moves it off the shoulder.
const BODY_OWNER: StringName = &"fireman_carried"
## carry_ended reasons.
const SET_DOWN: StringName = &"set_down"
const ON_TABLE: StringName = &"table"
const FELLED: StringName = &"felled"
const GRABBED: StringName = &"grabbed"
const DISCONNECTED: StringName = &"disconnected"
const LOST: StringName = &"lost"
## MNR-14: set down into an empty tub.
const ON_TUB: StringName = &"tub"

## carrier -> body
var carries: Dictionary = {}
## Every set-down and drop, for GEN-13's diff log: {tick, carrier, body, tile, table (bool), reason}.
var diff_log: Array[Dictionary] = []
var _run: RunState = null


func stage() -> int:
	return StageTable.Stage.MINERS


func order() -> int:
	return 15


func system_name() -> String:
	return "fireman_carry"


func bind(run: RunState) -> void:
	_run = run
	if run.miner_state != null:
		run.miner_state.state_changed.connect(_on_state_changed)


func is_carrying(carrier: int) -> bool:
	return carries.has(carrier)


## The body a miner carries, or 0.
func body_carried_by(carrier: int) -> int:
	return int(Variants.number(carries.get(carrier, 0)))


## The miner carrying a body, or 0.
func carrier_of(body: int) -> int:
	for raw: Variant in carries.keys():
		if int(Variants.number(carries[raw])) == body:
			return int(Variants.number(raw))
	return 0


## True if `lifter` may lift `body` now (before the lift starts: hands free).
func may_lift(run: RunState, lifter: int, body: int) -> bool:
	return _liftable(run, lifter, body) and run.inventory != null and run.inventory.hands_of(lifter).free_hand == null \
		and not run.inventory.hands_of(lifter).two_handed


## The 2 s lift (movement.carry_lift_time, held interact). The lamp hooks when it starts and
## unhooks if it is cancelled; nothing else is spent. MNR-05's ring, VIS-07's felt use and MOD-08's
## POINT (a Hired Hand) all start it.
func lift_action(run: RunState, lifter: int, body: int) -> TimedAction:
	var a: TimedAction = TimedAction.make(lifter, &"lift_body", Tuning.f(&"movement.carry_lift_time"), InputRecord.HOLD_INTERACT)
	a.target_entity = body
	a.reach = Tuning.f(&"vision.touch_range_tiles")
	var hooked: Array[bool] = [false]
	a.valid = func() -> bool:
		if not hooked[0]:
			return may_lift(run, lifter, body)
		return _liftable(run, lifter, body) and run.inventory.hands_of(lifter).two_handed
	a.on_start = func() -> void:
		hooked[0] = may_lift(run, lifter, body) and run.inventory.begin_two_handed(run, lifter)
	a.cancelled.connect(func(_action: TimedAction, _reason: StringName) -> void:
		if hooked[0]:
			hooked[0] = false
			run.inventory.end_two_handed(lifter))
	a.effect = func() -> void: _begin(run, lifter, body)
	return a


## Sets the body down at once: onto a free medbay table within touch range, else on the carrier's
## tile; the lamp goes back to the hand. NET-11 calls this with DISCONNECTED (no knock: a fireman's
## carry makes none). Returns false if the miner carries nothing.
func set_down(run: RunState, carrier: int, reason: StringName = SET_DOWN) -> bool:
	if not carries.has(carrier):
		return false
	var body: int = body_carried_by(carrier)
	var b: BodyState = run.falls.body_of(body) if run.falls != null else null
	var at: SimEntity = run.registry.get_entity(carrier)
	var table: Vector2i = _free_table_near(run, at.position) if at != null and reason == SET_DOWN else Vector2i(-1, -1)
	var on_table: bool = table.x >= 0 and run.base_camp.cupboard().lay(table, body)
	# MNR-14: beside an empty tub, it goes into the tub.
	if not on_table and at != null and reason == SET_DOWN and run.tubs != null and b != null:
		b.carried_by = 0
		if run.tubs.take_body(run, body, at.position):
			diff_log.append({"tick": run.tick, "carrier": carrier, "body": body, "tile": at.tile(), "table": false, "reason": "tub"})
			_end(run, carrier, body, ON_TUB)
			return true
		b.carried_by = carrier
	if b != null:
		b.carried_by = 0
		b.on_table = on_table
		b.on_floor = not on_table
	if at != null:
		_place(run, body, Vector2(table) + Vector2(0.5, 0.5) if on_table else at.position)
	var tile: Vector2i = table if on_table else (at.tile() if at != null else Vector2i.ZERO)
	diff_log.append({"tick": run.tick, "carrier": carrier, "body": body, "tile": tile, "table": on_table, "reason": str(reason)})
	_end(run, carrier, body, ON_TABLE if on_table else reason)
	return true


func tick(run: RunState) -> void:
	_run = run
	var carriers: Array = carries.keys()
	carriers.sort()
	for raw: Variant in carriers:
		var carrier: int = int(Variants.number(raw))
		var body: int = body_carried_by(carrier)
		if not run.registry.has(carrier) or run.falls == null or run.falls.body_of(body) == null:
			# The body rose or vanished under it (never in play: revival needs a table).
			if run.falls != null and run.falls.body_of(body) != null:
				run.falls.body_of(body).carried_by = 0
			_end(run, carrier, body, LOST)
			continue
		# The body rides on the carrier, moved right after the carrier walks, so every later stage
		# (creatures, vision) finds it on the carrier's tile.
		_place(run, body, run.registry.get_entity(carrier).position)
		var slot: int = _slot_of(run, carrier)
		var c: InputBuffer.Consumed = run.input_for(slot) if slot >= 0 else null
		if c != null and run.inventory.is_fresh(carrier, c.record.holds, InputRecord.HOLD_INTERACT):
			run.inventory.mark_spent(carrier, InputRecord.HOLD_INTERACT)
			set_down(run, carrier)


func _place(run: RunState, body: int, at: Vector2) -> void:
	if run.movement != null:
		run.movement.place(run, body, at)
	elif run.registry.has(body):
		run.registry.move(body, at)


func _liftable(run: RunState, lifter: int, body: int) -> bool:
	if lifter == body or carries.has(lifter) or run.falls == null or run.inventory == null:
		return false
	var b: BodyState = run.falls.body_of(body)
	if b == null or b.held_by_trap or b.carried_by != 0 or b.dragged_by != 0:
		return false
	# MNR-14: not off a stretcher or out of a tub someone holds.
	if b.on_load != 0 and ((run.loads != null and run.loads.is_held(b.on_load)) or (run.tubs != null and run.tubs.is_held(b.on_load))):
		return false
	if run.miner_state != null and run.miner_state.miner(lifter) != null:
		return run.miner_state.life(lifter) == MinerTransitions.Life.UPRIGHT
	return true


func _begin(run: RunState, carrier: int, body: int) -> void:
	var b: BodyState = run.falls.body_of(body)
	if b.on_table and run.base_camp != null:
		run.base_camp.cupboard().take_off(body)
	# MNR-14: lifted off a stretcher or out of a tub.
	if b.on_load != 0 and run.loads != null:
		run.loads.take_body_off(run, body)
	if b.on_load != 0 and run.tubs != null:
		run.tubs.take_body_off(run, body)
	b.carried_by = carrier
	b.on_floor = false
	b.on_table = false
	carries[carrier] = body
	_place(run, body, run.registry.get_entity(carrier).position)
	_pace(run, carrier, true)
	_lock(run, body, true)
	run.inventory.set_load(carrier, ItemKinds.LOAD_BODY)
	if run.replication != null:
		run.replication.set_attached(body, true)
	# The lift's hold must be released before interact sets the body down.
	run.inventory.mark_spent(carrier, InputRecord.HOLD_INTERACT)
	carry_started.emit(carrier, body)


func _end(run: RunState, carrier: int, body: int, reason: StringName) -> void:
	carries.erase(carrier)
	_pace(run, carrier, false)
	_lock(run, body, false)
	if run.inventory != null:
		run.inventory.set_load(carrier, 0)
		if run.inventory.hands_of(carrier).two_handed:
			run.inventory.end_two_handed(carrier)
	if run.replication != null:
		run.replication.set_attached(body, false)
	carry_ended.emit(carrier, body, reason)


## Walk only (no running, no crouching) at the carry's speed, on heavy steps.
func _pace(run: RunState, carrier: int, on: bool) -> void:
	var slot: int = _slot_of(run, carrier)
	if slot < 0:
		return
	if not on:
		run.movement.set_constraint(slot, OWNER, null)
		run.movement.modifiers(slot).clear(OWNER)
		return
	var c: MinerMotion.Constraints = MinerMotion.Constraints.new()
	c.walk_only = true
	c.run_allowed = false
	run.movement.set_constraint(slot, OWNER, c)
	var factor: float = Tuning.f(&"movement.carry_fireman_speed") / Tuning.f(&"movement.walk_speed")
	run.movement.modifiers(slot).set_modifier(OWNER, factor, Tuning.f(&"noise.step_heavy_np"))


func _lock(run: RunState, body: int, on: bool) -> void:
	var slot: int = _slot_of(run, body)
	if slot < 0:
		return
	var c: MinerMotion.Constraints = null
	if on:
		c = MinerMotion.Constraints.new()
		c.movement_off = true
		c.facing_lock = true
	run.movement.set_constraint(slot, BODY_OWNER, c)


## The nearest free medbay table whose centre is within touch range (Proposed), or (-1, -1).
func _free_table_near(run: RunState, at: Vector2) -> Vector2i:
	if run.base_camp == null:
		return Vector2i(-1, -1)
	var medbay: Medbay = run.base_camp.cupboard()
	var reach: float = Tuning.f(&"vision.touch_range_tiles")
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: float = INF
	for t: Vector2i in medbay.tables:
		if int(Variants.number(medbay.bodies.get(t, 0))) != 0:
			continue
		var d: float = at.distance_to(Vector2(t) + Vector2(0.5, 0.5))
		if d <= reach + 1e-9 and d < best_d:
			best = t
			best_d = d
	return best


## Smothered or felled (unconscious, dead) or grabbed: the body drops on the carrier's own tile.
func _on_state_changed(entity: int, _old: int, new: int, _cause: String) -> void:
	if not carries.has(entity) or _run == null:
		return
	if new == MinerTransitions.Life.GRABBED:
		set_down(_run, entity, GRABBED)
	elif new == MinerTransitions.Life.UNCONSCIOUS or new == MinerTransitions.Life.DEAD:
		set_down(_run, entity, FELLED)


func _slot_of(run: RunState, entity: int) -> int:
	if run.movement == null:
		return -1
	for slot: int in run.movement.miner_slots():
		if run.movement.miner(slot).entity_id == entity:
			return slot
	return -1


func write_state(writer: SimStateWriter) -> void:
	var carriers: Array = carries.keys()
	carriers.sort()
	writer.put_i64(carriers.size())
	for raw: Variant in carriers:
		writer.put_i64(int(Variants.number(raw)))
		writer.put_i64(int(Variants.number(carries[raw])))
	writer.put_i64(diff_log.size())
