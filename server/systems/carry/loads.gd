class_name Loads
extends SimSystem
## MNR-14 (stage MINERS, right after movement): the stretcher and the drum gear (Gameplay §4.3,
## §11.4, §11.5; GDD §15.8). Each is an ITEM entity of the LOAD class, lying where it was set down
## with its heading in its item state, so GEN-13 keeps it like any item. Interact on one, in touch
## range of an end, takes the nearer free end in movement.load_take_time of held interact, the lamp
## hooked from the start.
##
## A load's carriers stand at its ends (LoadSegment): their own steps are replaced, a stretcher's
## carriers face its heading and cannot turn, and nobody moves a load alone, but for one miner with
## an empty stretcher, who moves it on their own input at walking pace (movement.walk_speed; a
## second miner taking the other end makes it a carry for two). While it moves every carrier steps
## every movement.step_interval (9 np), and a knock sounds at its centre (12 np). Interact or set
## down again by either carrier sets the load down at once and every lamp goes back to its hand; a
## carrier grabbed, caught, felled or disconnected (NET-11) sets it down the same way, never with a
## knock (Proposed).
##
## A body laid on a stretcher (the ring's lay, Stretcher) rides at its centre. Set down with the
## body within touch range of a free medbay table, it goes onto the table
## movement.stretcher_to_table_time later, unless the stretcher is taken up first (Proposed). The
## drum gear set down within touch range of an empty tub goes into it (Tubs). Server-only: others
## see the load as its own entity (kind and heading) and its carriers by their held bits.

signal carry_started(carrier: int, load_entity: int)
signal carry_ended(carrier: int, load_entity: int, reason: StringName)

## The carriers' gait constraint and pace.
const OWNER: StringName = &"load_carry"
## carry_ended reasons.
const SET_DOWN: StringName = &"set_down"
const GRABBED: StringName = &"grabbed"
const CAUGHT: StringName = &"caught"
const FELLED: StringName = &"felled"
const DISCONNECTED: StringName = &"disconnected"
const LOST: StringName = &"lost"
## Which place a miner takes on a load.
enum Place { NONE, FRONT, REAR }


## A load someone holds, or with a body on its way to a table.
class Load:
	extends RefCounted
	var uid: int = 0
	## Its item entity now (GEN-13 gives a load put back a new one).
	var entity: int = 0
	var segment: LoadSegment = null
	var front: int = 0
	var rear: int = 0
	## The body lying on a stretcher.
	var body: int = 0
	var table: Vector2i = Vector2i(-1, -1)
	## The tick the body goes onto `table`, -1 for none.
	var transfer_at: int = -1

	func carriers() -> Array[int]:
		var out: Array[int] = []
		for c: int in [front, rear]:
			if c != 0:
				out.append(c)
		return out

	func held() -> bool:
		return front != 0 or rear != 0


## uid -> Load
var active: Dictionary = {}
## Every set-down, drop and transfer, for GEN-13 and the tests: {tick, uid, kind, tile, reason}.
var diff_log: Array[Dictionary] = []
## Every knock: {tick, uid, tile}.
var knocks: Array[Dictionary] = []
var _run: RunState = null


func stage() -> int:
	return StageTable.Stage.MINERS


func order() -> int:
	return 12


func system_name() -> String:
	return "loads"


func bind(run: RunState) -> void:
	_run = run
	if run.inventory != null:
		run.inventory.targets.providers.append(_targets)
	if run.miner_state != null:
		run.miner_state.state_changed.connect(_on_state_changed)
	if run.ring != null:
		var down: Array[int] = [MinerTransitions.Life.UNCONSCIOUS, MinerTransitions.Life.DEAD]
		var can_lay: Callable = func(r: RunState, actor: int, target: int) -> bool: return Stretcher.may_lay(r, actor, target)
		var lay: Callable = func(r: RunState, actor: int, target: int) -> TimedAction: return Stretcher.lay_action(r, actor, target)
		run.ring.registry.register("lay", down, can_lay, lay, false, "lift")


#region Queries

## A load laid in the mine (GEN-10's placement, tests): its entity, or 0 when that pose would
## overlap rock.
func place(run: RunState, kind: ItemKinds.Kind, at: Vector2, heading: int = 0) -> int:
	var seg: LoadSegment = LoadSegment.make(kind, at, heading)
	if seg.collides(seg.x, seg.y, seg.heading, _solid):
		push_error("Loads.place: a %s at %s overlaps rock" % [ItemKinds.text_key(kind), at])
		return 0
	return run.inventory.world.put(run, run.inventory.world.make(kind, 1, {"heading": seg.heading}), at)


## The load whose end `carrier` holds, or null.
func load_of_carrier(carrier: int) -> Load:
	if carrier == 0:
		return null
	for raw: Variant in active.values():
		var l: Load = raw
		if l.front == carrier or l.rear == carrier:
			return l
	return null


func carrying(carrier: int) -> bool:
	return load_of_carrier(carrier) != null


## Someone holds the load with this uid.
func is_held(uid: int) -> bool:
	var l: Load = active.get(uid, null)
	return l != null and l.held()


## The body lying on the stretcher with this uid, or 0.
func body_on(run: RunState, uid: int) -> int:
	var l: Load = active.get(uid, null)
	if l != null:
		return l.body
	var e: int = entity_of(run, uid)
	var it: Item = run.inventory.world.item_at(e) if e != 0 else null
	var body: int = int(Variants.number(it.state.get("body", 0))) if it != null else 0
	var b: BodyState = run.falls.body_of(body) if run.falls != null and body != 0 else null
	return body if b != null and b.on_load == uid else 0


## The pose of the load with this uid (the live one while it is held), or null.
func segment_of(run: RunState, uid: int) -> LoadSegment:
	var l: Load = active.get(uid, null)
	if l != null:
		return l.segment
	var e: int = entity_of(run, uid)
	return _segment_for(run, e) if e != 0 else null


## The entity of the load with this uid lying in the mine, or 0.
func entity_of(run: RunState, uid: int, hint: int = 0) -> int:
	var world: ItemWorld = run.inventory.world
	var l: Load = active.get(uid, null)
	for e: int in [hint, l.entity if l != null else 0]:
		var it: Item = world.item_at(e) if e != 0 else null
		if it != null and it.uid == uid:
			return e
	for raw: Variant in world.items.keys():
		var it: Item = world.items[raw]
		if it.uid == uid:
			return int(Variants.number(raw))
	return 0


## Loads of `kinds` (default the stretcher and the drum gear) lying with their centre within `r`
## of `at`, ascending entity.
func lying(run: RunState, at: Vector2, r: float, kinds: Array[int] = [ItemKinds.Kind.STRETCHER, ItemKinds.Kind.DRUM_GEAR]) -> Array[int]:
	var out: Array[int] = []
	var world: ItemWorld = run.inventory.world
	for id: int in run.registry.ids_near_cell(WorldCoords.cell_of(Vector2i(floori(at.x), floori(at.y))), 1):
		var it: Item = world.item_at(id)
		if it == null or not kinds.has(it.kind):
			continue
		if run.registry.get_entity(id).position.distance_to(at) <= r + 1e-9:
			out.append(id)
	return out

#endregion


#region Taking an end

## Whether `miner` may take a place on the load at `load_entity` now.
func may_take(run: RunState, miner: int, load_entity: int) -> bool:
	if not _free_to_take(run, miner):
		return false
	return place_for(run, miner, load_entity) != Place.NONE


## The place `miner` would take: the free end nearer them (the front on a tie), else none.
func place_for(run: RunState, miner: int, load_entity: int) -> Place:
	var it: Item = run.inventory.world.item_at(load_entity)
	var me: SimEntity = run.registry.get_entity(miner)
	if it == null or me == null or not (it.kind == ItemKinds.Kind.STRETCHER or it.kind == ItemKinds.Kind.DRUM_GEAR):
		return Place.NONE
	var l: Load = active.get(it.uid, null)
	var front_free: bool = l == null or l.front == 0
	var rear_free: bool = l == null or l.rear == 0
	if not front_free and not rear_free:
		return Place.NONE
	var seg: LoadSegment = l.segment if l != null else _segment_for(run, load_entity)
	if front_free and rear_free:
		return Place.FRONT if me.position.distance_to(seg.front_end()) <= me.position.distance_to(seg.rear_end()) else Place.REAR
	return Place.FRONT if front_free else Place.REAR


## Taking an end: movement.load_take_time of held interact in touch range of the end taken; the lamp
## hooks when it starts and comes back if it is let go early.
func take_action(run: RunState, miner: int, load_entity: int) -> TimedAction:
	var a: TimedAction = TimedAction.make(miner, &"take_load", Tuning.f(&"movement.load_take_time"), InputRecord.HOLD_INTERACT)
	var it: Item = run.inventory.world.item_at(load_entity)
	var uid: int = it.uid if it != null else 0
	a.target_point = _handle_near(run, load_entity, miner)
	a.reach = Tuning.f(&"vision.touch_range_tiles")
	var hooked: Array[bool] = [false]
	a.valid = func() -> bool:
		var e: int = entity_of(run, uid, load_entity)
		if not hooked[0]:
			return e != 0 and may_take(run, miner, e)
		return e != 0 and place_for(run, miner, e) != Place.NONE and run.inventory.hands_of(miner).two_handed
	a.on_start = func() -> void:
		hooked[0] = may_take(run, miner, load_entity) and run.inventory.begin_two_handed(run, miner)
	a.cancelled.connect(func(_action: TimedAction, _reason: StringName) -> void:
		if hooked[0]:
			hooked[0] = false
			run.inventory.end_two_handed(miner))
	a.effect = func() -> void: _take(run, miner, uid)
	return a


func _take(run: RunState, miner: int, uid: int) -> void:
	var e: int = entity_of(run, uid)
	var where: Place = place_for(run, miner, e) if e != 0 else Place.NONE
	if where == Place.NONE:
		run.inventory.end_two_handed(miner)
		return
	var l: Load = _activate(run, uid, e)
	if where == Place.FRONT:
		l.front = miner
	else:
		l.rear = miner
	# Taken up again: no body goes onto a table, and the gear leaves its tub.
	l.transfer_at = -1
	if run.tubs != null:
		run.tubs.unload(run, e)
	_gait(run, miner, l, true)
	run.inventory.set_load(miner, ItemKinds.LOAD_END)
	# The take's hold must be released before interact sets the load down.
	run.inventory.mark_spent(miner, InputRecord.HOLD_INTERACT)
	carry_started.emit(miner, l.entity)
	_place_all(run, l)

#endregion


#region Setting down

## Sets `carrier`'s load down at once where it is, with every carrier letting go and every lamp
## back in its hand; never a knock. False if the miner holds none.
func set_down(run: RunState, carrier: int, reason: StringName = SET_DOWN) -> bool:
	var l: Load = load_of_carrier(carrier)
	if l == null:
		return false
	for c: int in l.carriers():
		_let_go(run, l, c, reason)
	_rest(run, l, reason)
	return true


## A load comes to rest: its pose kept on its item, logged for GEN-13; a loaded stretcher by a free
## table starts its transfer, and the drum gear by an empty tub goes in.
func _rest(run: RunState, l: Load, reason: StringName) -> void:
	_place_load(run, l)
	var it: Item = run.inventory.world.item_at(l.entity)
	if it != null:
		it.state["heading"] = l.segment.heading
		run.inventory.world.moved(run, l.entity)
	var tile: Vector2i = Vector2i(floori(l.segment.x), floori(l.segment.y))
	diff_log.append({"tick": run.tick, "uid": l.uid, "kind": l.segment.kind, "tile": tile, "reason": str(reason)})
	if l.segment.kind == ItemKinds.Kind.STRETCHER and l.body != 0:
		l.table = Stretcher.free_table_near(run, l.segment.centre())
		if l.table.x >= 0:
			l.transfer_at = run.tick + roundi(Tuning.f(&"movement.stretcher_to_table_time") * Tuning.f(&"net.tick_hz"))
	elif l.segment.kind == ItemKinds.Kind.DRUM_GEAR and run.tubs != null:
		run.tubs.take_gear(run, l.entity)
	if l.transfer_at < 0:
		active.erase(l.uid)


func _let_go(run: RunState, l: Load, carrier: int, reason: StringName) -> void:
	if l.front == carrier:
		l.front = 0
	if l.rear == carrier:
		l.rear = 0
	_gait(run, carrier, l, false)
	if run.inventory != null:
		run.inventory.set_load(carrier, 0)
		if run.inventory.hands_of(carrier).two_handed:
			run.inventory.end_two_handed(carrier)
	carry_ended.emit(carrier, l.entity, reason)


## Grabbed, caught or felled: the load goes down that tick (NET-11 calls set_down on a drop).
func _on_state_changed(entity: int, _old: int, new: int, _cause: String) -> void:
	if _run == null or not carrying(entity):
		return
	match new:
		MinerTransitions.Life.GRABBED:
			set_down(_run, entity, GRABBED)
		MinerTransitions.Life.CAUGHT:
			set_down(_run, entity, CAUGHT)
		MinerTransitions.Life.UNCONSCIOUS, MinerTransitions.Life.DEAD:
			set_down(_run, entity, FELLED)

#endregion


#region The body on a stretcher

## The ring's lay ends: the body lies on the stretcher at `stretcher_entity`, at its centre.
func lay_body(run: RunState, stretcher_entity: int, body: int) -> bool:
	var it: Item = run.inventory.world.item_at(stretcher_entity)
	var b: BodyState = run.falls.body_of(body) if run.falls != null else null
	if it == null or it.kind != ItemKinds.Kind.STRETCHER or b == null or is_held(it.uid) or body_on(run, it.uid) != 0:
		return false
	if b.on_table and run.base_camp != null:
		run.base_camp.cupboard().take_off(body)
	b.on_table = false
	b.on_floor = false
	b.on_load = it.uid
	it.state["body"] = body
	var l: Load = active.get(it.uid, null)
	if l != null:
		l.body = body
	_place(run, body, run.registry.get_entity(stretcher_entity).position)
	run.inventory.world.moved(run, stretcher_entity)
	return true


## A body taken off its stretcher (a lift into a fireman's carry): no longer on it.
func take_body_off(run: RunState, body: int) -> void:
	var b: BodyState = run.falls.body_of(body) if run.falls != null else null
	if b == null or b.on_load == 0:
		return
	var e: int = entity_of(run, b.on_load)
	var it: Item = run.inventory.world.item_at(e) if e != 0 else null
	if it == null or it.kind != ItemKinds.Kind.STRETCHER:
		return
	it.state.erase("body")
	var l: Load = active.get(b.on_load, null)
	if l != null:
		l.body = 0
		l.transfer_at = -1
		if not l.held():
			active.erase(l.uid)
	b.on_load = 0
	b.on_floor = true


func _onto_table(run: RunState, l: Load) -> void:
	l.transfer_at = -1
	var b: BodyState = run.falls.body_of(l.body) if run.falls != null else null
	if b == null or b.on_load != l.uid or not run.base_camp.cupboard().lay(l.table, l.body):
		return
	var it: Item = run.inventory.world.item_at(l.entity)
	if it != null:
		it.state.erase("body")
	b.on_load = 0
	b.on_table = true
	b.on_floor = false
	_place(run, l.body, Vector2(l.table) + Vector2(0.5, 0.5))
	diff_log.append({"tick": run.tick, "uid": l.uid, "kind": l.segment.kind, "tile": l.table, "reason": "table", "body": l.body})
	Log.info("stretcher %d: body %d onto the medbay table at %s" % [l.uid, l.body, l.table])
	l.body = 0

#endregion


func tick(run: RunState) -> void:
	_run = run
	if run.movement == null or run.inventory == null:
		return
	for slot: int in run.movement.miner_slots():
		_input(run, slot)
	var uids: Array = active.keys()
	uids.sort()
	for raw: Variant in uids:
		var l: Load = active.get(raw, null)
		if l == null:
			continue
		l.entity = entity_of(run, l.uid, l.entity)
		if l.entity == 0:
			# Gone from under them (never in play): every carrier lets go.
			for c: int in l.carriers():
				_let_go(run, l, c, LOST)
			active.erase(raw)
			continue
		if (l.front != 0 and l.rear != 0) or (l.held() and l.segment.kind == ItemKinds.Kind.STRETCHER and l.body == 0):
			_carry(run, l)
		else:
			_place_all(run, l)
		if not l.held() and l.transfer_at >= 0 and run.tick >= l.transfer_at:
			_onto_table(run, l)
			active.erase(raw)


## A carrier's interact or set down sets their load down; anyone else's interact on a load takes it.
func _input(run: RunState, slot: int) -> void:
	var entity: int = run.movement.miner(slot).entity_id
	var c: InputBuffer.Consumed = run.input_for(slot)
	if c == null:
		return
	if carrying(entity):
		for bit: int in [InputRecord.HOLD_INTERACT, InputRecord.HOLD_SET_DOWN]:
			if run.inventory.is_fresh(entity, c.record.holds, bit):
				run.inventory.mark_spent(entity, bit)
				set_down(run, entity)
				return
		return
	if run.inventory.actions.has(entity) or run.inventory.is_partner(entity) \
			or not run.inventory.is_fresh(entity, c.record.holds, InputRecord.HOLD_INTERACT):
		return
	# Both hands already full (a fireman's carry, a tub): their own owner's interact. (The
	# inventory makes a miner's hands, with their lamp check, on its own first tick.)
	if not run.inventory.hands.has(entity) or run.inventory.hands_of(entity).two_handed:
		return
	var t: Dictionary = run.inventory.targets.pick(run, entity, slot, run.inventory.world)
	if StringName(str(t.get("kind", ""))) != &"load":
		return
	run.inventory.mark_spent(entity, InputRecord.HOLD_INTERACT)
	run.inventory.start_action(run, take_action(run, entity, int(Variants.number(t["id"]))))


## Two carriers: the segment steps on their pushes, and they, the load and its body follow. One
## carrier with an empty stretcher steps it alone, at walking pace.
func _carry(run: RunState, l: Load) -> void:
	var front_slot: int = _slot_of(run, l.front)
	var rear_slot: int = _slot_of(run, l.rear)
	var alone: bool = l.front == 0 or l.rear == 0
	if alone:
		front_slot = maxi(front_slot, rear_slot)
		rear_slot = front_slot
	l.segment.speed = Tuning.f(&"movement.walk_speed") if alone else LoadSegment.speed_of(l.segment.kind)
	var wounded: bool = _wounded(run, front_slot) or _wounded(run, rear_slot)
	var r: LoadSegment.Result = l.segment.step(_push(run, front_slot), _push(run, rear_slot), wounded, _solid)
	_place_all(run, l)
	if run.noise == null:
		return
	var centre: Vector2i = Vector2i(floori(l.segment.x), floori(l.segment.y))
	if r.knock:
		knocks.append({"tick": run.tick, "uid": l.uid, "tile": centre})
		run.noise.emit(NoiseTypes.Type.CARRY_KNOCK, centre, {"source": l.entity})
	var step: NoiseTypes.Type = NoiseTypes.Type.STEP_DRUM_GEAR if l.segment.kind == ItemKinds.Kind.DRUM_GEAR else NoiseTypes.Type.STEP_STRETCHER
	for _i: int in r.steps:
		for carrier: int in l.carriers():
			run.noise.emit(step, run.registry.get_entity(carrier).tile(), {"source": carrier})


## The load's item, its carriers at its ends (a stretcher's facing its heading) and its body at its
## centre.
func _place_all(run: RunState, l: Load) -> void:
	_place_load(run, l)
	var facing: int = l.segment.heading if l.segment.kind == ItemKinds.Kind.STRETCHER else -1
	for pair: Array in [[l.front, l.segment.front_end()], [l.rear, l.segment.rear_end()]]:
		var carrier: int = int(Variants.number(pair[0]))
		var slot: int = _slot_of(run, carrier)
		if carrier != 0 and slot >= 0:
			var at: Vector2 = pair[1]
			run.movement.carry(run, slot, at, facing)


func _place_load(run: RunState, l: Load) -> void:
	if run.registry.has(l.entity):
		run.registry.move(l.entity, l.segment.centre())
	var it: Item = run.inventory.world.item_at(l.entity)
	if it != null:
		it.state["heading"] = l.segment.heading
	if l.body != 0:
		_place(run, l.body, l.segment.centre())


func _place(run: RunState, entity: int, at: Vector2) -> void:
	if run.movement != null:
		run.movement.place(run, entity, at)
	elif run.registry.has(entity):
		run.registry.move(entity, at)


## A carrier's gait while they hold an end: no movement of their own (a stretcher's, no turning
## either).
func _gait(run: RunState, carrier: int, l: Load, on: bool) -> void:
	var slot: int = _slot_of(run, carrier)
	if slot < 0:
		return
	if not on:
		run.movement.set_constraint(slot, OWNER, null)
		return
	var c: MinerMotion.Constraints = MinerMotion.Constraints.new()
	c.movement_off = true
	c.facing_lock = l.segment.kind == ItemKinds.Kind.STRETCHER
	run.movement.set_constraint(slot, OWNER, c)


## A carrier's push this tick, from NET-03's consumed input (none yet: starved).
func _push(run: RunState, slot: int) -> LoadSegment.Push:
	var c: InputBuffer.Consumed = run.input_for(slot) if slot >= 0 else null
	if c == null:
		return LoadSegment.Push.of(InputRecord.NO_DIRECTION, run.tick, true)
	return LoadSegment.Push.of(c.record.move_dir, c.shown_tick, c.starved)


## Hurt or trap-wounded (MNR-03's wound slot).
func _wounded(run: RunState, slot: int) -> bool:
	var m: SpeedModifiers = run.movement.modifiers(slot) if slot >= 0 else null
	return m != null and m.wound


## The record for the load `uid` at `entity`, made from its item when nobody held it.
func _activate(run: RunState, uid: int, entity: int) -> Load:
	var l: Load = active.get(uid, null)
	if l == null:
		l = Load.new()
		l.uid = uid
		l.segment = _segment_for(run, entity)
		l.body = body_on(run, uid)
		active[uid] = l
	l.entity = entity
	return l


func _segment_for(run: RunState, entity: int) -> LoadSegment:
	var it: Item = run.inventory.world.item_at(entity)
	var at: Vector2 = run.registry.get_entity(entity).position
	return LoadSegment.make(it.kind, at, int(Variants.number(it.state.get("heading", 0))))


## The end of the load at `entity` that `miner` would take (else the nearer one).
func _handle_near(run: RunState, entity: int, miner: int) -> Vector2:
	var it: Item = run.inventory.world.item_at(entity)
	if it == null:
		return Vector2.ZERO
	var l: Load = active.get(it.uid, null)
	var seg: LoadSegment = l.segment if l != null else _segment_for(run, entity)
	var me: Vector2 = run.registry.get_entity(miner).position
	match place_for(run, miner, entity):
		Place.FRONT:
			return seg.front_end()
		Place.REAR:
			return seg.rear_end()
	return seg.front_end() if me.distance_to(seg.front_end()) <= me.distance_to(seg.rear_end()) else seg.rear_end()


## Upright, both hands free for it and holding nothing else.
func _free_to_take(run: RunState, miner: int) -> bool:
	if carrying(miner) or (run.carry != null and run.carry.is_carrying(miner)) or (run.tubs != null and run.tubs.holding(miner)):
		return false
	if run.miner_state != null and run.miner_state.miner(miner) != null and run.miner_state.life(miner) != MinerTransitions.Life.UPRIGHT:
		return false
	var h: HandsAndBelt = run.inventory.hands_of(miner)
	return h.free_hand == null and not h.two_handed


## MNR-04's interaction targets: every load lying with an end in touch range; its point the nearer
## end (the drum gear in a tub too: taking it lifts it out).
func _targets(run: RunState, _actor: int, at: Vector2, reach: float) -> Array:
	var out: Array = []
	for e: int in lying(run, at, reach + Tuning.f(&"movement.stretcher_length")):
		var it: Item = run.inventory.world.item_at(e)
		var l: Load = active.get(it.uid, null)
		var seg: LoadSegment = l.segment if l != null else _segment_for(run, e)
		var end: Vector2 = seg.front_end() if at.distance_to(seg.front_end()) <= at.distance_to(seg.rear_end()) else seg.rear_end()
		if at.distance_to(end) <= reach + 1e-9:
			out.append({"kind": &"load", "id": e, "point": end})
	return out


func _solid(tile: Vector2i) -> bool:
	return _run != null and _run.mine != null and not _run.mine.native.is_walkable(tile)


func _slot_of(run: RunState, entity: int) -> int:
	if run.movement == null or entity == 0:
		return -1
	for slot: int in run.movement.miner_slots():
		if run.movement.miner(slot).entity_id == entity:
			return slot
	return -1


func write_state(writer: SimStateWriter) -> void:
	var uids: Array = active.keys()
	uids.sort()
	writer.put_i64(uids.size())
	for raw: Variant in uids:
		var l: Load = active[raw]
		writer.put_i64(l.uid)
		l.segment.write_state(writer)
		writer.put_i64(l.front)
		writer.put_i64(l.rear)
		writer.put_i64(l.body)
		writer.put_i64(l.transfer_at)
	writer.put_i64(knocks.size())
	writer.put_i64(diff_log.size())


## NET-09: a carry in progress is not kept (a resume finds the load set down where it was, GEN-13
## keeping its pose); a body on its way to a table is, by the ticks left.
func save_state() -> Dictionary:
	var transfers: Dictionary = {}
	for raw: Variant in active.keys():
		var l: Load = active[raw]
		if not l.held() and l.transfer_at >= 0 and _run != null:
			transfers[str(l.uid)] = {"left": l.transfer_at - _run.tick, "x": l.table.x, "y": l.table.y, "body": l.body}
	return {"transfers": transfers}


func load_state(run: RunState, state: Dictionary) -> void:
	active.clear()
	var transfers: Dictionary = Variants.dict(state.get("transfers", {}))
	for raw: Variant in transfers.keys():
		var d: Dictionary = Variants.dict(transfers[raw])
		var l: Load = Load.new()
		l.uid = int(str(raw))
		l.body = int(Variants.number(d.get("body", 0)))
		l.table = Vector2i(int(Variants.number(d.get("x", -1))), int(Variants.number(d.get("y", -1))))
		l.transfer_at = run.tick + int(Variants.number(d.get("left", 0)))
		l.entity = entity_of(run, l.uid)
		if l.entity != 0:
			l.segment = _segment_for(run, l.entity)
			active[l.uid] = l
