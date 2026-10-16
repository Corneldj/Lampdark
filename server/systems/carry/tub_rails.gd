class_name TubRails
extends SimSystem
## MNR-14 (stage MINERS, after LoadCarry): tubs on their rails (Gameplay §4.3, §12.4; GDD §15.8). A tub
## is an ITEM entity of the LOAD class standing on a rail tile (a walkable tile with GEN-01's rail
## state bit). A pusher takes hold with both hands in movement.load_take_time of held interact (the
## lamp hooked from the start, Proposed), up to two at once, and pushes with their movement input:
## the tub runs only along the rails, at movement.carry_tub_speed_one for one pusher pushing its way
## and movement.carry_tub_speed_two for two; opposed pushes stop it, with no knock (Proposed). At a
## rail junction it takes the branch nearest the push (Proposed), and it stops at the last rail tile
## before rubble, a shut gate or the rails' end. While it moves it rumbles (14 np) as it starts and
## every movement.step_interval after (Proposed). Its pushers stand behind it, moved with it.
##
## It holds exactly one cargo: a body, the drum gear, or up to movement.tub_max_cans cans. A body
## set down from a fireman's carry, or the drum gear set down, within touch range of an empty tub
## goes into it; a can goes in by interact with it in the free hand. A tap of interact (released
## before the hold completes) unloads instead (Proposed): a can back into the empty free hand, else
## the ring on a body in it, whose lift takes it out. The gear comes out by taking an end (LoadCarry).
## Interact or set down again lets go; a pusher grabbed, caught, felled or disconnected lets go at
## once. Cans in a tub live in its item state, so GEN-13 keeps them with it. Server-only.

signal carry_started(pusher: int, tub: int)
signal carry_ended(pusher: int, tub: int, reason: StringName)

const OWNER: StringName = &"tub_hold"
const LET_GO: StringName = &"let_go"
const GRABBED: StringName = &"grabbed"
const CAUGHT: StringName = &"caught"
const FELLED: StringName = &"felled"
const DISCONNECTED: StringName = &"disconnected"
const LOST: StringName = &"lost"
const MAX_PUSHERS: int = 2
## A tub fills a tile: its pushers stand this far behind its centre, plus a body's radius.
const HALF_LENGTH: float = 0.5
## Its rim, from its centre, where a hand takes it.
const RIM: float = 0.45
const CENTRE_EPS: float = 1e-6
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]


## A tub someone holds.
class Tub:
	extends RefCounted
	var uid: int = 0
	var entity: int = 0
	## The centre, on a rail tile's centre or between two along `dir`.
	var x: float = 0.0
	var y: float = 0.0
	## The way it last moved (ZERO before it has).
	var dir: Vector2i = Vector2i.ZERO
	var pushers: Array[int] = []
	var moving: bool = false
	var rumble_accum: float = 0.0


## uid -> Tub
var held: Dictionary = {}
## Every rumble, stop and cargo change, for the tests and telemetry: {tick, uid, what, tile}.
var log: Array[Dictionary] = []
var _run: RunState = null


func stage() -> int:
	return StageTable.Stage.MINERS


func order() -> int:
	return 13


func system_name() -> String:
	return "tubs"


func bind(run: RunState) -> void:
	_run = run
	if run.inventory != null:
		run.inventory.targets.providers.append(_targets)
	if run.miner_state != null:
		run.miner_state.state_changed.connect(_on_state_changed)


#region Queries

## A tub on the rails (GEN-10's placement, tests): its entity, or 0 off the rails.
func place(run: RunState, tile: Vector2i, axis: Vector2i = Vector2i(1, 0)) -> int:
	if not on_rails(run, tile):
		push_error("TubRails.place: %s is not a rail tile" % tile)
		return 0
	var it: Item = run.inventory.world.make(ItemKinds.Kind.TUB, 1, {"heading": _heading_of(axis), "cans": []})
	return run.inventory.world.put(run, it, Vector2(tile) + Vector2(0.5, 0.5))


## A walkable tile with rails: the only ground a tub runs on.
static func on_rails(run: RunState, tile: Vector2i) -> bool:
	return run.mine != null and run.mine.native.is_walkable(tile) and (run.mine.native.state_at(tile) & CellFile.STATE_RAIL) != 0


func holding(miner: int) -> bool:
	return tub_held_by(miner) != null


func tub_held_by(miner: int) -> Tub:
	for raw: Variant in held.values():
		var t: Tub = raw
		if t.pushers.has(miner):
			return t
	return null


## Whether anyone holds the tub with this uid.
func is_held(uid: int) -> bool:
	return held.has(uid)


## The tub entity carrying `entity` (a body or the drum gear), or 0.
func tub_of(run: RunState, entity: int) -> int:
	var b: BodyState = run.falls.body_of(entity) if run.falls != null else null
	var it: Item = run.inventory.world.item_at(entity)
	var uid: int = 0
	if b != null:
		uid = b.on_load
	elif it != null:
		uid = int(Variants.number(it.state.get("in_tub", 0)))
	var tub: int = _entity_of(run, uid) if uid != 0 else 0
	var t: Item = run.inventory.world.item_at(tub) if tub != 0 else null
	return tub if t != null and t.kind == ItemKinds.Kind.TUB else 0


## What a tub holds: "" (empty), "body", "gear" or "cans".
func cargo(run: RunState, tub: int) -> String:
	var it: Item = run.inventory.world.item_at(tub)
	if it == null:
		return ""
	if int(Variants.number(it.state.get("body", 0))) != 0:
		return "body"
	if int(Variants.number(it.state.get("gear", 0))) != 0:
		return "gear"
	return "cans" if cans_in(run, tub) > 0 else ""


func cans_in(run: RunState, tub: int) -> int:
	var it: Item = run.inventory.world.item_at(tub)
	return Variants.array(it.state.get("cans", [])).size() if it != null else 0


## Empty tubs with their centre within touch range of `at`, nearest first (ties to the lower id).
func empty_near(run: RunState, at: Vector2) -> int:
	var best: int = 0
	var best_d: float = INF
	for e: int in run.loads.lying(run, at, Tuning.f(&"vision.touch_range_tiles"), [ItemKinds.Kind.TUB] as Array[int]):
		var d: float = run.registry.get_entity(e).position.distance_to(at)
		if cargo(run, e).is_empty() and d < best_d:
			best = e
			best_d = d
	return best

#endregion


#region Cargo

## A body set down beside an empty tub goes into it (MNR-13's set-down asks first). False if none.
func take_body(run: RunState, body: int, at: Vector2) -> bool:
	var tub: int = empty_near(run, at) if run.loads != null else 0
	var b: BodyState = run.falls.body_of(body) if run.falls != null else null
	if tub == 0 or b == null:
		return false
	var it: Item = run.inventory.world.item_at(tub)
	it.state["body"] = body
	b.on_load = it.uid
	b.on_floor = false
	b.on_table = false
	_place_body(run, body, run.registry.get_entity(tub).position)
	_note(run, it.uid, "body in", tub)
	run.inventory.world.moved(run, tub)
	return true


## The drum gear set down beside an empty tub goes into it, lying along the rails.
func take_gear(run: RunState, gear: int) -> bool:
	var g: Item = run.inventory.world.item_at(gear)
	if g == null or g.kind != ItemKinds.Kind.DRUM_GEAR or run.loads == null:
		return false
	var tub: int = empty_near(run, run.registry.get_entity(gear).position)
	if tub == 0:
		return false
	var it: Item = run.inventory.world.item_at(tub)
	it.state["gear"] = g.uid
	g.state["in_tub"] = it.uid
	g.state["heading"] = int(Variants.number(it.state.get("heading", 0)))
	run.registry.move(gear, run.registry.get_entity(tub).position)
	run.inventory.world.moved(run, gear)
	run.inventory.world.moved(run, tub)
	_note(run, it.uid, "gear in", tub)
	return true


## A can from `miner`'s free hand goes in (no body or gear in it, fewer than the most cans).
func put_can(run: RunState, miner: int, tub: int) -> bool:
	var h: HandsAndBelt = run.inventory.hands_of(miner)
	var it: Item = run.inventory.world.item_at(tub)
	if it == null or h.free_hand == null or h.free_hand.kind != ItemKinds.Kind.PARAFFIN_CAN:
		return false
	var c: String = cargo(run, tub)
	if not (c.is_empty() or c == "cans") or cans_in(run, tub) >= Tuning.i(&"movement.tub_max_cans"):
		_note(run, it.uid, "refused", tub)
		return false
	var can: Item = h.free_hand
	h.free_hand = null
	var cans: Array = Variants.array(it.state.get("cans", []))
	cans.append(StateDicts.item_to(can))
	it.state["cans"] = cans
	run.inventory.world.note(run, &"into_tub", can, miner)
	run.inventory.changed.emit(miner)
	run.inventory.world.moved(run, tub)
	_note(run, it.uid, "can in", tub)
	return true


## The last can put in comes out into `miner`'s empty free hand.
func take_can(run: RunState, miner: int, tub: int) -> bool:
	var h: HandsAndBelt = run.inventory.hands_of(miner)
	var it: Item = run.inventory.world.item_at(tub)
	if it == null or h.free_hand != null or h.two_handed or cans_in(run, tub) == 0:
		return false
	var cans: Array = Variants.array(it.state.get("cans", []))
	var can: Item = StateDicts.item_from(cans.pop_back())
	it.state["cans"] = cans
	h.free_hand = can
	run.inventory.world.note(run, &"from_tub", can, miner)
	run.inventory.changed.emit(miner)
	run.inventory.world.moved(run, tub)
	_note(run, it.uid, "can out", tub)
	return true


## The drum gear taken up (LoadCarry): out of its tub, if it was in one.
func unload(run: RunState, gear: int) -> void:
	var g: Item = run.inventory.world.item_at(gear)
	if g == null or not g.state.has("in_tub"):
		return
	var tub: int = _entity_of(run, int(Variants.number(g.state["in_tub"])))
	g.state.erase("in_tub")
	var it: Item = run.inventory.world.item_at(tub) if tub != 0 else null
	if it != null:
		it.state.erase("gear")
		run.inventory.world.moved(run, tub)
		_note(run, it.uid, "gear out", tub)


## A tap on a tub with a body in it opens the ring on the body (its lift takes it out).
func _ring_on_body(run: RunState, miner: int, tub: int) -> void:
	var it: Item = run.inventory.world.item_at(tub)
	var body: int = int(Variants.number(it.state.get("body", 0))) if it != null else 0
	if body != 0 and run.ring != null:
		run.ring.open(run, miner, body)


## A body lifted out of its tub (MNR-13's lift).
func take_body_off(run: RunState, body: int) -> void:
	var b: BodyState = run.falls.body_of(body) if run.falls != null else null
	if b == null or b.on_load == 0:
		return
	var tub: int = _entity_of(run, b.on_load)
	var it: Item = run.inventory.world.item_at(tub) if tub != 0 else null
	if it == null or it.kind != ItemKinds.Kind.TUB:
		return
	it.state.erase("body")
	b.on_load = 0
	b.on_floor = true
	run.inventory.world.moved(run, tub)
	_note(run, it.uid, "body out", tub)

#endregion


#region Holding

func may_hold(run: RunState, miner: int, tub: int) -> bool:
	var it: Item = run.inventory.world.item_at(tub)
	if it == null or it.kind != ItemKinds.Kind.TUB or holding(miner):
		return false
	if (run.loads != null and run.loads.carrying(miner)) or (run.carry != null and run.carry.is_carrying(miner)):
		return false
	if run.miner_state != null and run.miner_state.miner(miner) != null and run.miner_state.life(miner) != MinerTransitions.Life.UPRIGHT:
		return false
	var h: HandsAndBelt = run.inventory.hands_of(miner)
	var t: Tub = held.get(it.uid, null)
	return h.free_hand == null and not h.two_handed and (t == null or t.pushers.size() < MAX_PUSHERS)


## Taking hold: movement.load_take_time of held interact, the lamp hooked from the start. A tap
## released early unloads instead: a can into the empty free hand, else the ring on a body in it.
func hold_action(run: RunState, miner: int, tub: int) -> TimedAction:
	var a: TimedAction = TimedAction.make(miner, &"take_hold", Tuning.f(&"movement.load_take_time"), InputRecord.HOLD_INTERACT)
	a.target_entity = tub
	a.reach = Tuning.f(&"vision.touch_range_tiles")
	var uid: int = run.inventory.world.item_at(tub).uid
	var hooked: Array[bool] = [false]
	a.valid = func() -> bool:
		if not hooked[0]:
			return may_hold(run, miner, tub)
		return run.inventory.world.item_at(tub) != null and run.inventory.hands_of(miner).two_handed
	a.on_start = func() -> void:
		hooked[0] = may_hold(run, miner, tub) and run.inventory.begin_two_handed(run, miner)
	a.cancelled.connect(func(_action: TimedAction, reason: StringName) -> void:
		if hooked[0]:
			hooked[0] = false
			run.inventory.end_two_handed(miner)
		if reason == TimedAction.RELEASED and not take_can(run, miner, tub):
			_ring_on_body(run, miner, tub))
	a.effect = func() -> void: _hold(run, miner, uid)
	return a


func _hold(run: RunState, miner: int, uid: int) -> void:
	var tub: int = _entity_of(run, uid)
	var it: Item = run.inventory.world.item_at(tub) if tub != 0 else null
	var t: Tub = held.get(uid, null)
	if it == null or (t != null and t.pushers.size() >= MAX_PUSHERS):
		run.inventory.end_two_handed(miner)
		return
	if t == null:
		t = Tub.new()
		t.uid = uid
		t.entity = tub
		var at: Vector2 = run.registry.get_entity(tub).position
		t.x = at.x
		t.y = at.y
		held[uid] = t
	t.pushers.append(miner)
	var slot: int = _slot_of(run, miner)
	if slot >= 0:
		var c: MinerMotion.Constraints = MinerMotion.Constraints.new()
		c.movement_off = true
		run.movement.set_constraint(slot, OWNER, c)
	run.inventory.set_load(miner, ItemKinds.LOAD_TUB)
	run.inventory.mark_spent(miner, InputRecord.HOLD_INTERACT)
	carry_started.emit(miner, tub)


## A pusher lets go at once (their lamp back in the hand); the tub stays where it is.
func let_go(run: RunState, miner: int, reason: StringName = LET_GO) -> bool:
	var t: Tub = tub_held_by(miner)
	if t == null:
		return false
	t.pushers.erase(miner)
	var slot: int = _slot_of(run, miner)
	if slot >= 0:
		run.movement.set_constraint(slot, OWNER, null)
	run.inventory.set_load(miner, 0)
	if run.inventory.hands_of(miner).two_handed:
		run.inventory.end_two_handed(miner)
	carry_ended.emit(miner, t.entity, reason)
	if t.pushers.is_empty():
		_rest(run, t)
	return true


func _rest(run: RunState, t: Tub) -> void:
	held.erase(t.uid)
	if t.moving:
		_note(run, t.uid, "stop", t.entity)
	var it: Item = run.inventory.world.item_at(t.entity)
	if it != null:
		run.inventory.world.moved(run, t.entity)


func _on_state_changed(entity: int, _old: int, new: int, _cause: String) -> void:
	if _run == null or not holding(entity):
		return
	match new:
		MinerTransitions.Life.GRABBED:
			let_go(_run, entity, GRABBED)
		MinerTransitions.Life.CAUGHT:
			let_go(_run, entity, CAUGHT)
		MinerTransitions.Life.UNCONSCIOUS, MinerTransitions.Life.DEAD:
			let_go(_run, entity, FELLED)

#endregion


func tick(run: RunState) -> void:
	_run = run
	if run.movement == null or run.inventory == null:
		return
	for slot: int in run.movement.miner_slots():
		_input(run, slot)
	var uids: Array = held.keys()
	uids.sort()
	for raw: Variant in uids:
		var t: Tub = held.get(raw, null)
		if t == null:
			continue
		t.entity = _entity_of(run, t.uid, t.entity)
		if t.entity == 0:
			for p: int in t.pushers.duplicate():
				let_go(run, p, LOST)
			held.erase(raw)
			continue
		_push(run, t)


## A pusher's interact or set down lets go; anyone's interact on a tub puts a can in or takes hold.
func _input(run: RunState, slot: int) -> void:
	var entity: int = run.movement.miner(slot).entity_id
	var c: InputBuffer.Consumed = run.input_for(slot)
	if c == null:
		return
	if holding(entity):
		for bit: int in [InputRecord.HOLD_INTERACT, InputRecord.HOLD_SET_DOWN]:
			if run.inventory.is_fresh(entity, c.record.holds, bit):
				run.inventory.mark_spent(entity, bit)
				let_go(run, entity)
				return
		return
	if run.inventory.actions.has(entity) or run.inventory.is_partner(entity) \
			or not run.inventory.is_fresh(entity, c.record.holds, InputRecord.HOLD_INTERACT):
		return
	# Both hands already full (a fireman's carry, a load's end): their own owner's interact. (The
	# inventory makes a miner's hands, with their lamp check, on its own first tick.)
	if not run.inventory.hands.has(entity) or run.inventory.hands_of(entity).two_handed:
		return
	var t: Dictionary = run.inventory.targets.pick(run, entity, slot, run.inventory.world)
	if StringName(str(t.get("kind", ""))) != &"tub":
		return
	run.inventory.mark_spent(entity, InputRecord.HOLD_INTERACT)
	var tub: int = int(Variants.number(t["id"]))
	var h: HandsAndBelt = run.inventory.hands_of(entity)
	if h.free_hand != null and h.free_hand.kind == ItemKinds.Kind.PARAFFIN_CAN:
		put_can(run, entity, tub)
		return
	run.inventory.start_action(run, hold_action(run, entity, tub))


## One tick of pushing: along the rails by the pushers' inputs, its cargo and pushers with it.
func _push(run: RunState, t: Tub) -> void:
	var pushes: Array[Vector2] = []
	for p: int in t.pushers:
		var slot: int = _slot_of(run, p)
		var c: InputBuffer.Consumed = run.input_for(slot) if slot >= 0 else null
		if c != null and not c.starved and c.record.move_dir != InputRecord.NO_DIRECTION:
			var u: PackedFloat64Array = MinerMotion.direction(c.record.move_dir)
			pushes.append(Vector2(u[0], u[1]))
	var dt: float = 1.0 / Tuning.f(&"net.tick_hz")
	var left: float = 0.0
	var dir: Vector2i = _choose(run, t, pushes)
	if dir != Vector2i.ZERO:
		var within: float = _within()
		var pushing: int = 0
		var against: int = 0
		for p: Vector2 in pushes:
			var d: float = p.dot(Vector2(dir))
			if d >= within:
				pushing += 1
			elif d <= -within:
				against += 1
		if against == 0 and pushing > 0:
			left = Tuning.f(&"movement.carry_tub_speed_one" if pushing == 1 else &"movement.carry_tub_speed_two") * dt
	var moved: float = 0.0
	while left > CENTRE_EPS and dir != Vector2i.ZERO:
		t.dir = dir
		var to: PackedFloat64Array = _next_centre(t, dir)
		if not on_rails(run, Vector2i(floori(to[0]), floori(to[1]))):
			break
		var gap: float = absf(to[0] - t.x) + absf(to[1] - t.y)
		var step: float = minf(gap, left)
		t.x += dir.x * step
		t.y += dir.y * step
		left -= step
		moved += step
		if step >= gap - CENTRE_EPS:
			t.x = to[0]
			t.y = to[1]
			dir = _choose(run, t, pushes)
	var was: bool = t.moving
	t.moving = moved > 0.0
	_place(run, t)
	if t.moving:
		var it: Item = run.inventory.world.item_at(t.entity)
		if it != null:
			it.state["heading"] = _heading_of(t.dir)
		t.rumble_accum += dt
		if not was:
			t.rumble_accum = 0.0
			_rumble(run, t)
		var interval: float = Tuning.f(&"movement.step_interval")
		while t.rumble_accum >= interval - 1e-9:
			t.rumble_accum -= interval
			_rumble(run, t)
	elif was:
		_note(run, t.uid, "stop", t.entity)


## The least share of a push along a way that pushes it that way (the cosine of
## movement.tub_push_angle).
static func _within() -> float:
	return LbDetMath.cos_deg(Tuning.f(&"movement.tub_push_angle"))


## The next rail tile centre along `dir`: the neighbour's from a centre, else the one ahead on the
## segment the tub is on.
func _next_centre(t: Tub, dir: Vector2i) -> PackedFloat64Array:
	var cx: float = floorf(t.x) + 0.5
	var cy: float = floorf(t.y) + 0.5
	if absf(t.x - cx) < CENTRE_EPS and absf(t.y - cy) < CENTRE_EPS:
		return PackedFloat64Array([cx + dir.x, cy + dir.y])
	if dir.x != 0:
		var kx: float = floorf(t.x - 0.5)
		return PackedFloat64Array([kx + 1.5 if dir.x > 0 else kx + 0.5, t.y])
	var ky: float = floorf(t.y - 0.5)
	return PackedFloat64Array([t.x, ky + 1.5 if dir.y > 0 else ky + 0.5])


## The way the tub goes from where it is: along its segment (either way) between tile centres, or
## the rail neighbour nearest the pushes' sum at a centre; ZERO when no way lies within
## movement.tub_push_angle of the push.
func _choose(run: RunState, t: Tub, pushes: Array[Vector2]) -> Vector2i:
	var sum: Vector2 = Vector2.ZERO
	for p: Vector2 in pushes:
		sum += p
	if sum.length_squared() < 1e-12:
		return Vector2i.ZERO
	sum = sum.normalized()
	var cx: float = floorf(t.x) + 0.5
	var cy: float = floorf(t.y) + 0.5
	var here: Vector2i = Vector2i(floori(t.x), floori(t.y))
	var options: Array[Vector2i] = []
	if absf(t.x - cx) < CENTRE_EPS and absf(t.y - cy) < CENTRE_EPS:
		for d: Vector2i in DIRS:
			if on_rails(run, here + d):
				options.append(d)
	else:
		var axis: Vector2i = Vector2i(1, 0) if absf(t.y - cy) < CENTRE_EPS else Vector2i(0, 1)
		options = [axis, -axis]
	var best: Vector2i = Vector2i.ZERO
	var best_dot: float = _within() - 1e-9
	for d: Vector2i in options:
		var dot: float = sum.dot(Vector2(d))
		if dot > best_dot:
			best = d
			best_dot = dot
	return best


## The tub, its cargo and its pushers where it now stands: pushers behind it (else moved with it,
## else left, and a pusher left out of touch range lets go).
func _place(run: RunState, t: Tub) -> void:
	var at: Vector2 = Vector2(t.x, t.y)
	var before: Vector2 = run.registry.get_entity(t.entity).position
	run.registry.move(t.entity, at)
	var it: Item = run.inventory.world.item_at(t.entity)
	if it == null:
		return
	var body: int = int(Variants.number(it.state.get("body", 0)))
	if body != 0:
		_place_body(run, body, at)
	var gear_uid: int = int(Variants.number(it.state.get("gear", 0)))
	var gear: int = run.loads.entity_of(run, gear_uid) if gear_uid != 0 and run.loads != null else 0
	if gear != 0:
		run.registry.move(gear, at)
	if t.dir == Vector2i.ZERO or at == before:
		return
	var r: float = Tuning.f(&"movement.body_radius")
	var behind: Vector2 = at - Vector2(t.dir) * (HALF_LENGTH + r)
	for p: int in t.pushers.duplicate():
		var slot: int = _slot_of(run, p)
		var me: SimEntity = run.registry.get_entity(p)
		if slot < 0 or me == null:
			continue
		var to: Vector2 = behind
		if _body_hits(run, to, r):
			to = me.position + (at - before)
			if _body_hits(run, to, r):
				to = me.position
		run.movement.carry(run, slot, to)
		if to.distance_to(at) > Tuning.f(&"vision.touch_range_tiles") + Tuning.f(&"items.range_tolerance"):
			let_go(run, p, LET_GO)


func _place_body(run: RunState, body: int, at: Vector2) -> void:
	if run.movement != null:
		run.movement.place(run, body, at)
	elif run.registry.has(body):
		run.registry.move(body, at)


func _body_hits(run: RunState, at: Vector2, r: float) -> bool:
	for ty: int in range(floori(at.y - r), floori(at.y + r) + 1):
		for tx: int in range(floori(at.x - r), floori(at.x + r) + 1):
			if run.mine != null and not run.mine.native.is_walkable(Vector2i(tx, ty)):
				var near: Vector2 = at.clamp(Vector2(tx, ty), Vector2(tx + 1, ty + 1))
				if near.distance_squared_to(at) < r * r - 1e-9:
					return true
	return false


func _rumble(run: RunState, t: Tub) -> void:
	var tile: Vector2i = Vector2i(floori(t.x), floori(t.y))
	_note(run, t.uid, "rumble", t.entity)
	if run.noise != null:
		run.noise.emit(NoiseTypes.Type.TUB_RUMBLE, tile, {"source": t.entity})


func _note(run: RunState, uid: int, what: String, entity: int) -> void:
	var e: SimEntity = run.registry.get_entity(entity) if entity != 0 else null
	log.append({"tick": run.tick, "uid": uid, "what": what, "tile": e.tile() if e != null else Vector2i.ZERO})


## MNR-04's interaction targets: every tub in touch range, its point the rim nearer the actor (so
## a tub is taken hold of over a body lying in it; a tap opens the ring on that body).
func _targets(run: RunState, _actor: int, at: Vector2, reach: float) -> Array:
	var out: Array = []
	if run.loads == null:
		return out
	for e: int in run.loads.lying(run, at, reach, [ItemKinds.Kind.TUB] as Array[int]):
		var centre: Vector2 = run.registry.get_entity(e).position
		var d: Vector2 = at - centre
		var rim: Vector2 = centre + (d.normalized() * minf(RIM, d.length()) if d.length() > 1e-6 else Vector2.ZERO)
		out.append({"kind": &"tub", "id": e, "point": rim})
	return out


func _entity_of(run: RunState, uid: int, hint: int = 0) -> int:
	if run.loads != null:
		return run.loads.entity_of(run, uid, hint)
	return 0


static func _heading_of(axis: Vector2i) -> int:
	if axis == Vector2i(0, 1):
		return 16384
	if axis == Vector2i(-1, 0):
		return 32768
	if axis == Vector2i(0, -1):
		return 49152
	return 0


func _slot_of(run: RunState, entity: int) -> int:
	if run.movement == null or entity == 0:
		return -1
	for slot: int in run.movement.miner_slots():
		if run.movement.miner(slot).entity_id == entity:
			return slot
	return -1


func write_state(writer: SimStateWriter) -> void:
	var uids: Array = held.keys()
	uids.sort()
	writer.put_i64(uids.size())
	for raw: Variant in uids:
		var t: Tub = held[raw]
		writer.put_i64(t.uid)
		writer.put_f64(t.x)
		writer.put_f64(t.y)
		writer.put_i64(t.dir.x)
		writer.put_i64(t.dir.y)
		writer.put_i64(t.pushers.size())
		for p: int in t.pushers:
			writer.put_i64(p)
	writer.put_i64(log.size())
