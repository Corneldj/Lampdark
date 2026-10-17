class_name PhoneLines
extends SimSystem
## LFT-12 (Gameplay §6.6, §3.5, §4.10, §6.2, §6.4, §11.11, §12.5-12.7, A.3; GDD §15.4, §15.5): the
## pit phones and their lines to base camp's switchboard, and nothing else.
## - **First generation** (as its cell first commits): a phone's painted number, the next of a seeded
##   shuffle of 1 to phones.line_number_max (so a number says nothing of where; past the last, a dead
##   unnumbered phone), and its road home (LineRouter), both kept for the run (saves; GEN-13's LINE
##   record). The roads are found one a tick, in the order the phones generated (a few ms each:
##   Proposed, until GEN-11's worker can take them), the line dead until its road is stored. A fall
##   that came first, on its road, cuts it at once.
## - **Cut** by a roof fall across its road (HAZ-03's `fell`), for the run: `line_cut` for LFT-13.
## - **Live** with power (LFT-05's lines_live: never under Dead Lines, where no phone exists), unless
##   cut or unrouted.
## - **The crank:** interact at a phone, phones.crank_s with the free hand (a drawn revolver allows
##   it), then one crank (noise.phone_crank_np) at the phone. A live, free line then has its caller:
##   `calling` for the board (LFT-13). A dead line: the noise alone.
## - **On the phone:** the caller stays while conscious, not Grabbed, their own (a drop hands the
##   miner to a Hand) and within touch range; interact again hangs up. A grab, a fall, a drop,
##   leaving, a dead line or a cut ends the call that tick (`ended`: the operator's hiss, LFT-13).
## - **The call:** LFT-13's `answer` joins the operator's slot: SND-07's direct line, clean both ways,
##   the caller's voice still noise at the wall (SND-09's Road Graph events stand). While it is live,
##   both are heard (SND-09's "call").
## - **The bell:** LFT-13's `ring`, at a live phone: one bell (noise.phone_bell_np) for
##   phones.ring_burst_s; an interact while it rings answers it (Proposed: no crank). A dead line
##   does nothing.
## Hired Hands never crank, answer or hang up. Server-only: no route, cut or crossing leaves it; a
## phone's number, and what anyone beside it can tell (ringing, in use: SeenKind's phone bits), ride
## on its identity record (seen at 0.30), never below.

signal calling(number: int, miner: int)
## LFT-13: a rung phone answered at the wall, onto the operator who rang it.
signal answered(number: int, operator: int)
signal ended(number: int, why: String)
signal line_cut(number: int)

const KEY_PREFIX: String = "phone:"
## How often a live call marks both ends heard (ticks).
const HEARD_EVERY: int = 20

## id -> PitPhone, every phone generated this run (loaded or not).
var phones: Dictionary = {}
## How many numbers the pool has given.
var next_number: int = 0
## {tick, id, number, what, ...}: first generation, cranks, calls, cuts.
var history: Array[Dictionary] = []
var _by_number: Dictionary = {}
var _pool: Array = []
var _pending: Array[Vector2i] = []
## Phones whose road home is still to find, in the order they generated.
var _unrouted: Array[String] = []


func stage() -> int:
	return StageTable.Stage.WORLD


func order() -> int:
	return 64


func system_name() -> String:
	return "phone_lines"


## Hashed once a phone exists, so a run without one hashes as before.
func hashed() -> bool:
	return not phones.is_empty()


func bind(run: RunState) -> void:
	if run.mine != null:
		run.mine.native.cell_loaded.connect(func(cell: Vector2i) -> void:
			if not _pending.has(cell):
				_pending.append(cell))
		run.mine.native.cell_unloading.connect(func(cell: Vector2i) -> void: _on_unloading(run, cell))
		# NET-09: a resume's swap of the registry, each loaded cell's phones found again after it.
		run.cell_released.connect(func(cell: Vector2i) -> void: _on_unloading(run, cell))
		run.cell_remade.connect(func(cell: Vector2i) -> void:
			if not _pending.has(cell):
				_pending.append(cell))
	if run.collapses != null:
		run.collapses.fell.connect(func(pid: int, cell: Vector2i, tiles: Array[Vector2i]) -> void:
			on_tiles_fallen(run, cell, tiles, pid & 0xFFFF))
	if run.miner_state != null:
		run.miner_state.state_changed.connect(func(entity: int, _old: int, now: int, _cause: String) -> void:
			_on_life(run, entity, now))
	if run.inventory != null:
		run.inventory.targets.providers.append(_phone_targets)
	if run.feel != null:
		run.feel.register_felt_use(WorldIds.EntityKind.PHONE, func(r: RunState, miner: int, entity: int) -> bool:
			return interact(r, miner, entity))
	if run.diff_log != null:
		run.diff_log.register(DiffLog.Kind.LINE, _replay, Callable(), Callable(), KEY_PREFIX)


#region Lines

## A phone's first generation: its number, its road home (`route`: LineRouter's, or a test's), its
## record. Known already, it is as it was.
func meet(run: RunState, id: String, tile: Vector2i, route: Dictionary = {}) -> PitPhone:
	if phones.has(id):
		return phones[id]
	var p: PitPhone = PitPhone.new()
	p.id = id
	p.tile = tile
	p.cell = WorldCoords.cell_of(tile)
	var pool: Array = _number_pool(run)
	if next_number < pool.size():
		p.number = int(Variants.number(pool[next_number]))
		next_number += 1
	else:
		Log.warn("phone lines: the pool of %d numbers ran out; phone %s is dead and unnumbered" % [pool.size(), id])
	phones[id] = p
	if p.number > 0:
		_by_number[p.number] = id
	history.append({"tick": run.tick, "id": id, "number": p.number, "what": "generated"})
	if route.is_empty() and run.placed != null and run.placed.layouts != null:
		_unrouted.append(id)  # found on a later tick (route_next)
		_record(run, p)
		return p
	_store_route(run, p, route)
	return p


## How many phones still wait for their road home.
func pending_routes() -> int:
	return _unrouted.size()


## The next queued phone's road home (one a tick).
func route_next(run: RunState) -> bool:
	while not _unrouted.is_empty():
		var id: String = _unrouted.pop_front()
		var p: PitPhone = phones.get(id, null)
		if p == null or p.route_found_at >= 0:
			continue
		_store_route(run, p, LineRouter.route(run.placed.layouts, p.tile))
		return true
	return false


func _store_route(run: RunState, p: PitPhone, r: Dictionary) -> void:
	p.route_found_at = run.tick
	p.routed = Variants.flag(r.get("found", false))
	p.route_tiles = int(Variants.number(r.get("tiles", 0)))
	for raw: Variant in Variants.array(r.get("cells", [])):
		var c: Vector2i = raw
		p.route_cells.append(c)
	p.crossings = Variants.array(r.get("crossings", [])).duplicate(true)
	for raw: Variant in p.crossings:
		var pair: Array = raw
		var c: Vector2i = pair[0]
		if run.diff_log != null and not run.diff_log.payload_of(c, DiffLog.Kind.FALL, CollapsePoints.KEY_PREFIX + str(int(Variants.number(pair[1])))).is_empty():
			p.cut = true
	_record(run, p)
	history.append({"tick": run.tick, "id": p.id, "number": p.number, "what": "routed", "routed": p.routed, "cut": p.cut})


## The PHONE entity standing for a phone while its cell is loaded; its number on the identity record.
func attach(run: RunState, id: String, entity: int) -> void:
	var p: PitPhone = phones.get(id, null)
	if p == null:
		return
	p.entity = entity
	_show(run, p)


## Its identity record: the painted number, the bell ringing, someone on it (SeenKind's phone bits).
func _show(run: RunState, p: PitPhone) -> void:
	if run.replication == null or p.entity == 0:
		return
	var bits: int = p.number & SeenKind.PHONE_NUMBER_MASK
	if p.ringing_until >= run.tick:
		bits |= SeenKind.PHONE_RINGING
	if p.caller != 0:
		bits |= SeenKind.PHONE_BUSY
	run.replication.native.set_entity_held(p.entity, bits)


func of_number(number: int) -> PitPhone:
	return phones.get(_by_number.get(number, ""), null)


func of_entity(entity: int) -> PitPhone:
	if entity == 0:
		return null
	for raw: Variant in phones.keys():
		var p: PitPhone = phones[raw]
		if p.entity == entity:
			return p
	return null


## Power on (and never Dead Lines), numbered, routed and uncut.
func live(run: RunState, p: PitPhone) -> bool:
	return p.number > 0 and p.routed and not p.cut and run.power != null and run.power.lines_live()


## HAZ-03: a roof fell on `tiles` of `cell` (alternate `collapse`): every line across it is cut.
func on_tiles_fallen(run: RunState, cell: Vector2i, _tiles: Array[Vector2i], collapse: int) -> void:
	var ids: Array = phones.keys()
	ids.sort()
	for raw: Variant in ids:
		var p: PitPhone = phones[raw]
		if p.cut or not p.crosses(cell, collapse):
			continue
		p.cut = true
		_record(run, p)
		history.append({"tick": run.tick, "id": p.id, "number": p.number, "what": "cut", "cell": cell})
		Log.info("phone lines: line %d cut by a fall in %s" % [p.number, cell])
		if p.caller != 0:
			_end(run, p, "cut")
		line_cut.emit(p.number)


func _number_pool(run: RunState) -> Array:
	if _pool.is_empty():
		for i: int in Tuning.i(&"phones.line_number_max"):
			_pool.append(i + 1)
		# The seed's own shuffle, never a run stream: the same pool after any resume.
		var rng: LbRng = LbRng.from_seed(LbHash.sub_seed(run.header.run_seed, HashDomain.PHONES, PackedInt64Array([0]), 0))
		rng.shuffle(_pool)
	return _pool


func _record(run: RunState, p: PitPhone) -> void:
	if run.diff_log == null:
		return
	var crossings: Array = []
	for raw: Variant in p.crossings:
		var pair: Array = raw
		var c: Vector2i = pair[0]
		crossings.append([c.x, c.y, int(Variants.number(pair[1]))])
	run.diff_log.record(p.cell, DiffLog.Kind.LINE, KEY_PREFIX + p.id, {"number": p.number, "tile": [p.tile.x, p.tile.y],
		"routed": p.routed, "tiles": p.route_tiles, "crossings": crossings, "cut": p.cut})


## GEN-13: a phone known only from its record (its line kept in the log) is known again.
func _replay(_run: RunState, _cell: Vector2i, key: String, payload: Dictionary, _tick: int) -> void:
	var id: String = key.substr(KEY_PREFIX.length())
	if phones.has(id):
		return
	var p: PitPhone = PitPhone.new()
	p.id = id
	var at: Array = Variants.array(payload.get("tile", [0, 0]))
	p.tile = Vector2i(int(Variants.number(at[0])), int(Variants.number(at[1])))
	p.cell = WorldCoords.cell_of(p.tile)
	p.number = int(Variants.number(payload.get("number", 0)))
	p.routed = Variants.flag(payload.get("routed", false))
	p.route_tiles = int(Variants.number(payload.get("tiles", 0)))
	for raw: Variant in Variants.array(payload.get("crossings", [])):
		var t: Array = raw
		p.crossings.append([Vector2i(int(Variants.number(t[0])), int(Variants.number(t[1]))), int(Variants.number(t[2]))])
	p.cut = Variants.flag(payload.get("cut", false))
	p.route_found_at = 0 if p.routed or p.route_tiles > 0 else -1
	phones[id] = p
	if p.number > 0:
		_by_number[p.number] = id
	if p.route_found_at < 0 and not _unrouted.has(id):
		_unrouted.append(id)

#endregion

#region The phone

## LFT-13: the operator answers a calling line; `operator` is the board's headset slot.
func answer(run: RunState, number: int, operator: int) -> bool:
	var p: PitPhone = of_number(number)
	if p == null or p.state != PitPhone.State.CALLING or not live(run, p):
		return false
	return _connect(run, p, operator)


## LFT-13: the operator rings a line. At a live phone, one bell for phones.ring_burst_s; nothing at
## a dead one.
func ring(run: RunState, number: int, operator: int) -> bool:
	var p: PitPhone = of_number(number)
	if p == null or not live(run, p):
		return false
	var burst: float = Tuning.f(&"phones.ring_burst_s")
	p.ringing_until = run.tick + roundi(burst * Tuning.f(&"net.tick_hz"))
	p.ringing_by = operator
	_show(run, p)
	if run.noise != null:
		run.noise.emit(NoiseTypes.Type.PHONE_BELL, p.tile, {"duration_s": burst})
	history.append({"tick": run.tick, "id": p.id, "number": number, "what": "rung"})
	return true


## LFT-13: the seat changed hands: no bell still ringing answers onto whoever rang it.
func forget_rings() -> void:
	for raw: Variant in phones.keys():
		var p: PitPhone = phones[raw]
		p.ringing_by = -1


## LFT-13: the operator holds a call: the line goes quiet both ways, the caller stays on it in hiss.
func hold(run: RunState, number: int) -> bool:
	var p: PitPhone = of_number(number)
	if p == null or p.state != PitPhone.State.ON_CALL:
		return false
	var slot: int = _slot_of(run, p.caller)
	if run.voice != null and slot >= 0 and p.operator >= 0:
		run.voice.close_direct(slot, p.operator)
	p.state = PitPhone.State.HELD
	p.operator = -1
	history.append({"tick": run.tick, "id": p.id, "number": number, "what": "held"})
	return true


## LFT-13: back to a held call.
func resume(run: RunState, number: int, operator: int) -> bool:
	var p: PitPhone = of_number(number)
	if p == null or p.state != PitPhone.State.HELD or not live(run, p):
		return false
	return _connect(run, p, operator)


## Whether `miner` waits on a held line (its earpiece hisses).
func held_caller(miner: int) -> bool:
	for raw: Variant in phones.keys():
		var p: PitPhone = phones[raw]
		if p.caller == miner and p.state == PitPhone.State.HELD:
			return true
	return false


## LFT-13: the operator pulls the plug.
func hang_up(run: RunState, number: int) -> bool:
	var p: PitPhone = of_number(number)
	if p == null or p.caller == 0:
		return false
	_end(run, p, "operator")
	return true


## A miner's interact at a phone: hang up if on it, answer it if it rings, else crank it. False when
## nothing happens (a Hired Hand; another miner on it; the free hand full).
func interact(run: RunState, miner: int, entity: int) -> bool:
	var p: PitPhone = of_entity(entity)
	if p == null or _hand(run, miner):
		return false
	if p.caller == miner:
		_end(run, p, "hung up")
		return true
	if p.caller != 0:
		return false
	if p.ringing_until >= run.tick and live(run, p):
		p.caller = miner
		history.append({"tick": run.tick, "id": p.id, "number": p.number, "what": "answered", "by": miner})
		var operator: int = p.ringing_by
		if operator >= 0 and _connect(run, p, operator):
			answered.emit(p.number, operator)
			return true
		# LFT-13: whoever rang has left the board: the call waits there, its flap down (Proposed).
		p.state = PitPhone.State.CALLING
		p.ringing_until = -1
		_show(run, p)
		calling.emit(p.number, miner)
		return true
	if run.inventory == null or run.inventory.actions.has(miner) or run.inventory.free_hand_blocked(miner, &"phone"):
		return false
	return run.inventory.start_action(run, _crank(run, miner, p))


func _crank(run: RunState, miner: int, p: PitPhone) -> TimedAction:
	var a: TimedAction = TimedAction.make(miner, &"crank", Tuning.f(&"phones.crank_s"), InputRecord.HOLD_INTERACT)
	a.target_entity = p.entity
	a.reach = Tuning.f(&"vision.touch_range_tiles")
	a.valid = func() -> bool: return p.entity != 0 and run.registry.has(p.entity)
	a.effect = func() -> void: _cranked(run, miner, p)
	return a


func _cranked(run: RunState, miner: int, p: PitPhone) -> void:
	if run.noise != null:
		run.noise.emit(NoiseTypes.Type.PHONE_CRANK, p.tile, {"source": miner})
	var reached: bool = live(run, p) and p.caller == 0
	history.append({"tick": run.tick, "id": p.id, "number": p.number, "what": "cranked", "by": miner, "live": reached})
	if not reached:
		return
	p.caller = miner
	p.state = PitPhone.State.CALLING
	_show(run, p)
	calling.emit(p.number, miner)


func _connect(run: RunState, p: PitPhone, operator: int) -> bool:
	var slot: int = _slot_of(run, p.caller)
	if slot < 0 or operator < 0:
		return false
	# LFT-13: the board never patches: a line joins a phone to the headset, never to another phone.
	for raw: Variant in phones.keys():
		var other: PitPhone = phones[raw]
		if other.caller != 0 and _slot_of(run, other.caller) == operator:
			push_error("PhoneLines: line %d would be patched to line %d's caller" % [p.number, other.number])
			return false
	if run.voice != null:
		run.voice.open_direct(slot, operator)
	p.operator = operator
	p.state = PitPhone.State.ON_CALL
	p.ringing_until = -1
	_show(run, p)
	_mark_heard(run, slot, operator)
	history.append({"tick": run.tick, "id": p.id, "number": p.number, "what": "connected", "operator": operator})
	return true


func _end(run: RunState, p: PitPhone, why: String) -> void:
	if p.state == PitPhone.State.ON_CALL and p.operator >= 0 and run.voice != null:
		var slot: int = _slot_of(run, p.caller)
		if slot >= 0:
			run.voice.close_direct(slot, p.operator)
	history.append({"tick": run.tick, "id": p.id, "number": p.number, "what": "ended", "why": why})
	p.caller = 0
	p.operator = -1
	p.state = PitPhone.State.IDLE
	_show(run, p)
	ended.emit(p.number, why)


static func _mark_heard(run: RunState, caller_slot: int, operator: int) -> void:
	if run.heard != null:
		run.heard.mark_heard(caller_slot, &"call")
		run.heard.mark_heard(operator, &"call")

#endregion

func tick(run: RunState) -> void:
	_meet_pending(run)
	route_next(run)
	_interacts(run)
	_keep_calls(run)
	_bells_end(run)


## A bell's burst over: its record says so.
func _bells_end(run: RunState) -> void:
	for raw: Variant in phones.keys():
		var p: PitPhone = phones[raw]
		if p.ringing_until >= 0 and run.tick > p.ringing_until:
			p.ringing_until = -1
			_show(run, p)


func _meet_pending(run: RunState) -> void:
	if _pending.is_empty():
		return
	var cells: Array[Vector2i] = _pending.duplicate()
	_pending.clear()
	cells.sort()
	for cell: Vector2i in cells:
		if run.placed == null or run.mine == null or not run.mine.native.is_loaded(cell):
			continue
		for placed: Dictionary in run.placed.of_kind(cell, "phone"):
			var id: String = str(placed["id"])
			var tile: Vector2i = placed["tile"]
			meet(run, id, tile)
			attach(run, id, int(Variants.number(run.placed.phones.get(id, 0))))


func _on_unloading(run: RunState, cell: Vector2i) -> void:
	_pending.erase(cell)
	var ids: Array = phones.keys()
	ids.sort()
	for raw: Variant in ids:
		var p: PitPhone = phones[raw]
		if p.cell != cell:
			continue
		if p.caller != 0:
			_end(run, p, "gone")
		p.entity = 0


## A fresh interact whose target is a phone (MNR-04's pick) works it.
func _interacts(run: RunState) -> void:
	if run.inventory == null or run.movement == null:
		return
	var by_entity: Dictionary = {}
	for slot: int in run.movement.miner_slots():
		by_entity[run.movement.miner(slot).entity_id] = slot
	var miners: Array = by_entity.keys()
	miners.sort()
	for raw: Variant in miners:
		var m: int = int(Variants.number(raw))
		var slot: int = int(Variants.number(by_entity[raw]))
		var c: InputBuffer.Consumed = run.input_for(slot)
		if c == null or run.inventory.actions.has(m) or not run.inventory.is_fresh(m, c.record.holds, InputRecord.HOLD_INTERACT):
			continue
		var t: Dictionary = run.inventory.targets.pick(run, m, slot, run.inventory.world)
		if t.is_empty() or StringName(str(t["kind"])) != &"phone":
			continue
		run.inventory.mark_spent(m, InputRecord.HOLD_INTERACT)
		interact(run, m, int(Variants.number(t["id"])))


## Every caller still fit to stay on the line; a live call keeps both ends heard.
func _keep_calls(run: RunState) -> void:
	var ids: Array = phones.keys()
	ids.sort()
	for raw: Variant in ids:
		var p: PitPhone = phones[raw]
		if p.caller == 0:
			continue
		var why: String = _why_off(run, p)
		if not why.is_empty():
			_end(run, p, why)
		elif p.state == PitPhone.State.ON_CALL and run.tick % HEARD_EVERY == 0:
			_mark_heard(run, _slot_of(run, p.caller), p.operator)


## A caller grabbed or fallen leaves the line in the tick it happens: the call ends mid-word.
func _on_life(run: RunState, entity: int, now: int) -> void:
	var why: String = ""
	match now:
		MinerTransitions.Life.GRABBED:
			why = "grabbed"
		MinerTransitions.Life.UNCONSCIOUS, MinerTransitions.Life.DEAD:
			why = "fell"
	if why.is_empty():
		return
	var ids: Array = phones.keys()
	ids.sort()
	for raw: Variant in ids:
		var p: PitPhone = phones[raw]
		if p.caller == entity:
			_end(run, p, why)


func _why_off(run: RunState, p: PitPhone) -> String:
	if not run.registry.has(p.caller) or p.entity == 0 or not run.registry.has(p.entity):
		return "gone"
	if _hand(run, p.caller):
		return "dropped"
	if run.miner_state != null and run.miner_state.miner(p.caller) != null:
		match run.miner_state.life(p.caller):
			MinerTransitions.Life.GRABBED:
				return "grabbed"
			MinerTransitions.Life.UNCONSCIOUS, MinerTransitions.Life.DEAD:
				return "fell"
	var reach: float = Tuning.f(&"vision.touch_range_tiles") + Tuning.f(&"items.range_tolerance")
	if run.registry.get_entity(p.caller).position.distance_to(run.registry.get_entity(p.entity).position) > reach:
		return "left"
	if not live(run, p):
		return "dead"
	return ""


func _phone_targets(run: RunState, _actor: int, at: Vector2, reach: float) -> Array:
	var out: Array = []
	var ids: Array = phones.keys()
	ids.sort()
	for raw: Variant in ids:
		var p: PitPhone = phones[raw]
		if p.entity == 0 or not run.registry.has(p.entity):
			continue
		var pos: Vector2 = run.registry.get_entity(p.entity).position
		if at.distance_to(pos) <= reach:
			out.append({"kind": &"phone", "id": p.entity, "point": pos})
	return out


static func _hand(run: RunState, miner: int) -> bool:
	return run.crew != null and Variants.flag(run.crew.is_hand_driven.call(miner))


static func _slot_of(run: RunState, entity: int) -> int:
	if run.movement == null:
		return -1
	for slot: int in run.movement.miner_slots():
		if run.movement.miner(slot).entity_id == entity:
			return slot
	return -1


func write_state(writer: SimStateWriter) -> void:
	writer.put_i64(next_number)
	var ids: Array = phones.keys()
	ids.sort()
	writer.put_i64(ids.size())
	for raw: Variant in ids:
		var p: PitPhone = phones[raw]
		writer.put_string(p.id)
		writer.put_i64(p.number)
		writer.put_bool(p.routed)
		writer.put_i64(p.route_found_at)
		writer.put_bool(p.cut)
		writer.put_i32(p.state)
		writer.put_i64(p.caller)
		writer.put_i64(p.operator)


func save_state() -> Dictionary:
	var list: Array = []
	var ids: Array = phones.keys()
	ids.sort()
	for raw: Variant in ids:
		var p: PitPhone = phones[raw]
		list.append(p.to_dict())
	return {"next": next_number, "phones": list, "unrouted": _unrouted.duplicate()}


func load_state(_run: RunState, state: Dictionary) -> void:
	next_number = int(Variants.number(state.get("next", 0)))
	phones.clear()
	_by_number.clear()
	for raw: Variant in Variants.array(state.get("phones", [])):
		var p: PitPhone = PitPhone.from_dict(Variants.dict(raw))
		phones[p.id] = p
		if p.number > 0:
			_by_number[p.number] = p.id
	_unrouted.clear()
	for raw: Variant in Variants.array(state.get("unrouted", [])):
		_unrouted.append(str(raw))
