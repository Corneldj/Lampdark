class_name InventorySystem
extends SimSystem
## MNR-04 (stage MINERS, after movement): every miner's hands and belt, the items lying in the
## world, the timed-action runner and the interaction target. Each tick, per miner in entity
## order: read the selected slot (InputRecord.selected_slot), advance or cancel the running timed
## action, or start one: interact on an item picks it up, set-down lays the hand's lamp, a can or
## the selected item on the faced tile, use acts on the selected slot (a lamp there swaps with the
## lamp in hand; other kinds call their owning ticket's handler). Server-only: a miner's belt
## goes only to its owner (InventoryWire); others see only what is in its hands, at identity.

signal changed(entity: int)

## VIS-06: held_bits' low-byte flag for a lamp whose flame shows (lit and open).
const LAMP_LIT_BIT: int = ItemKinds.LAMP_LIT_BIT

var world: ItemWorld = ItemWorld.new()
var targets: InteractionTargets = InteractionTargets.new()
## entity -> HandsAndBelt
var hands: Dictionary = {}
## entity -> TimedAction (one per miner at a time, Proposed)
var actions: Dictionary = {}
## entity -> hold bits held through a finished, refused or cancelled action: they start nothing
## new until released.
var spent: Dictionary = {}
var _run: RunState = null
## kind -> (run, entity, slot) -> void: the owning ticket's use of a belt item (MNR-06 to MNR-16).
var use_handlers: Dictionary = {}
## MNR-16: Use on an empty selected slot: (run, entity, slot) -> void (a drawn revolver goes back).
var empty_slot_use: Callable = Callable()
## (run, slot) -> int: the held bits, for tests; unset reads NET-03's consumed input.
var holds_source: Callable = Callable()
var _starved: Dictionary = {}


func stage() -> int:
	return StageTable.Stage.MINERS


func order() -> int:
	return 20


func system_name() -> String:
	return "inventory"


## Hooks NET-03's input_starved (an action in progress is cancelled, nothing spent).
func bind(run: RunState) -> void:
	_run = run
	if run.inputs != null:
		run.inputs.input_starved.connect(func(slot: int) -> void: _starved[slot] = true)


#region The APIs every item ticket uses

## A miner's hands and belt, made at first sight with the run-start kit (§4.5): empty hands and
## belt; chalk, the Pocket Book and the lamp check present.
func hands_of(entity: int, check_number: int = 0) -> HandsAndBelt:
	if not hands.has(entity):
		hands[entity] = HandsAndBelt.create(entity, check_number)
	return hands[entity]


## Stores a whole item by the §4.3 rules; false (and nothing changes) when it does not fit.
func give(run: RunState, entity: int, item: Item) -> bool:
	var h: HandsAndBelt = hands_of(entity)
	if not h.fits(item):
		return false
	h.store(item)
	world.note(run, &"give", item, entity)
	changed.emit(entity)
	return true


## Takes a belt slot's contents out of the belt (for MNR-05's hand-over and taking).
func take(run: RunState, entity: int, slot: int) -> Item:
	var it: Item = hands_of(entity).take_slot(slot)
	if it != null:
		world.note(run, &"take", it, entity)
		changed.emit(entity)
	return it


func has(entity: int, kind: int) -> bool:
	return hands_of(entity).count_of(kind) > 0


## Spends `n` of a kind (a fuse fitted, a candle lit and set down); all or nothing.
func consume(run: RunState, entity: int, kind: ItemKinds.Kind, n: int = 1) -> bool:
	if not hands_of(entity).consume(kind, n):
		return false
	world.note(run, &"spend", Item.make(0, kind, n), entity)
	changed.emit(entity)
	return true


func hook_lamp(entity: int) -> void:
	var h: HandsAndBelt = hands_of(entity)
	if h.lamp_hand != null and ItemKinds.is_lamp(h.lamp_hand.kind):
		h.hooked = true
		changed.emit(entity)


func unhook_lamp(entity: int) -> void:
	var h: HandsAndBelt = hands_of(entity)
	if h.hooked:
		h.hooked = false
		changed.emit(entity)


func free_hand_blocked(entity: int, action: StringName) -> bool:
	return hands_of(entity).free_hand_blocked(action)


## A two-handed action starts (a carry, a carry end, a tub, freeing a trapped teammate): refused
## while the free hand holds anything; a lit candle in the lamp hand is set down burning on the
## miner's tile (Proposed); a lamp goes on the belt hook until end_two_handed().
func begin_two_handed(run: RunState, entity: int) -> bool:
	var h: HandsAndBelt = hands_of(entity)
	if h.free_hand != null or h.two_handed:
		return false
	if h.lamp_hand != null and h.lamp_hand.kind == ItemKinds.Kind.CANDLE:
		var candle: Item = h.lamp_hand
		h.lamp_hand = null
		var at: SimEntity = run.registry.get_entity(entity)
		world.put(run, candle, Vector2(at.tile()) + Vector2(0.5, 0.5), &"set_down", entity)
	hook_lamp(entity)
	h.two_handed = true
	changed.emit(entity)
	return true


func end_two_handed(entity: int) -> void:
	var h: HandsAndBelt = hands_of(entity)
	h.two_handed = false
	unhook_lamp(entity)
	changed.emit(entity)


## Starts a timed action; refused while the miner already runs one (Proposed: one at a time).
func start_action(run: RunState, a: TimedAction) -> bool:
	if actions.has(a.actor):
		return false
	a.started_tick = run.tick
	if run.miner_state != null and run.miner_state.miner(a.actor) != null:
		a.life_at_start = run.miner_state.life(a.actor)
	actions[a.actor] = a
	if a.on_start.is_valid():
		a.on_start.call()
	return true


## MNR-13, MNR-14: what fills both hands (ItemKinds.LOAD_BODY), shown on the identity record.
func set_load(entity: int, kind: int) -> void:
	var h: HandsAndBelt = hands_of(entity)
	if h.load_kind != kind:
		h.load_kind = kind
		changed.emit(entity)


## The identity-level "in hand" bits NET-04 sends others: low byte the lamp hand's kind (bit 7
## set while it hangs on the hook), high byte the free hand's kind, or what fills both hands during
## a carry (ItemKinds.LOAD_BODY: a body over the shoulder). Bit 6 of the low byte: the lamp's flame
## shows (lit and open, VIS-06's flame sprite). Never the belt.
func held_bits(entity: int) -> int:
	if not hands.has(entity):
		return 0
	var h: HandsAndBelt = hands[entity]
	var lo: int = (h.lamp_hand.kind | (0x80 if h.hooked else 0)) if h.lamp_hand != null else 0
	if h.lamp_hand != null and _run != null and _run.lamps != null:
		var l: GauzeLamp = _run.lamps.lamp_of_item(h.lamp_hand)
		if l != null and l.burning() and not l.shutter_closed:
			lo |= LAMP_LIT_BIT
	var hi: int = h.free_hand.kind if h.free_hand != null else 0
	if h.two_handed and h.load_kind != 0:
		hi = h.load_kind
	return lo | (hi << 8)


## The owner's own hands and belt, as InventoryWire encodes them (to that client only), with
## MNR-07's Check Lamp record while it is held.
func own_bytes(entity: int, check: Dictionary = {}) -> PackedByteArray:
	var h: HandsAndBelt = hands_of(entity)
	var slot_rows: Array = []
	for s: Item in h.slots:
		slot_rows.append([s.kind, s.count] if s != null else [0, 0])
	var lamp_state: Dictionary = h.lamp_hand.state if h.lamp_hand != null else {}
	return InventoryWire.encode({
		"lamp": [h.lamp_hand.kind, h.lamp_hand.count] if h.lamp_hand != null else [0, 0],
		"hooked": h.hooked,
		"two_handed": h.two_handed,
		"lamp_shut": Variants.flag(lamp_state.get("shutter", false)),
		"lamp_wick": int(Variants.number(lamp_state.get("wick", LampRules.WICK_NORMAL))),
		"free": [h.free_hand.kind, h.free_hand.count] if h.free_hand != null else [0, 0],
		"selected": h.selected,
		"slots": slot_rows,
		"lamp_check": h.lamp_check,
		"chalk": h.chalk,
		"pocket_book": h.pocket_book,
		"notes": h.notes.size(),
		"check": check,
	})

#endregion


func tick(run: RunState) -> void:
	if run.movement == null:
		return
	var order_by_entity: Dictionary = {}
	for slot: int in run.movement.miner_slots():
		order_by_entity[run.movement.miner(slot).entity_id] = slot
	var entities: Array = order_by_entity.keys()
	entities.sort()
	for raw: Variant in entities:
		var entity: int = int(Variants.number(raw))
		var slot: int = int(Variants.number(order_by_entity[raw]))
		var h: HandsAndBelt = hands_of(entity, slot + 1)
		var bits: int = _holds(run, slot)
		var c: InputBuffer.Consumed = run.input_for(slot)
		if c != null and h.selected != c.record.selected_slot():
			h.selected = mini(c.record.selected_slot(), h.slots.size() - 1)
			changed.emit(entity)
		spent[entity] = int(Variants.number(spent.get(entity, 0))) & bits
		var running: TimedAction = actions.get(entity, null)
		if running != null:
			_advance(run, running, slot, bits)
		else:
			_begin(run, entity, slot, bits)
	_starved.clear()


func _holds(run: RunState, slot: int) -> int:
	if holds_source.is_valid():
		return int(Variants.number(holds_source.call(run, slot)))
	var c: InputBuffer.Consumed = run.input_for(slot)
	return c.record.holds if c != null else 0


## MNR-05: this miner is holding for someone else's both-hold (their interact is not their own).
func is_partner(entity: int) -> bool:
	for raw: Variant in actions.keys():
		var a: TimedAction = actions[raw]
		if a.partner == entity or a.partners.has(entity):
			return true
	return false


## Another system's press (MNR-07's flint): held and not spent on a finished or refused action.
func is_fresh(entity: int, bits: int, bit: int) -> bool:
	return _fresh(entity, bits, bit)


func mark_spent(entity: int, bit: int) -> void:
	_spend(entity, bit)


func _fresh(entity: int, bits: int, bit: int) -> bool:
	return (bits & bit) != 0 and (int(Variants.number(spent.get(entity, 0))) & bit) == 0


func _spend(entity: int, bit: int) -> void:
	spent[entity] = int(Variants.number(spent.get(entity, 0))) | bit


func _caps(run: RunState, entity: int) -> Dictionary:
	if run.miner_state == null or run.miner_state.miner(entity) == null:
		return MinerTransitions.CAPABILITIES[MinerTransitions.Life.UPRIGHT]
	return run.miner_state.capabilities(entity)


func _allowed(run: RunState, entity: int, capability: StringName) -> bool:
	var caps: Dictionary = _caps(run, entity)
	if capability == &"belt":
		return Variants.flag(caps["belt"])
	var interact: String = str(caps["interact"])
	return interact == "yes" or interact == "reach"


func _begin(run: RunState, entity: int, slot: int, bits: int) -> void:
	if is_partner(entity):
		return
	if _fresh(entity, bits, InputRecord.HOLD_INTERACT):
		var target: Dictionary = targets.pick(run, entity, slot, world)
		if not target.is_empty() and StringName(str(target["kind"])) == &"item":
			_spend(entity, InputRecord.HOLD_INTERACT)
			_start_pick_up(run, entity, int(Variants.number(target["id"])))
	elif _fresh(entity, bits, InputRecord.HOLD_SET_DOWN):
		_spend(entity, InputRecord.HOLD_SET_DOWN)
		_start_set_down(run, entity, slot)
	elif _fresh(entity, bits, InputRecord.HOLD_USE):
		_spend(entity, InputRecord.HOLD_USE)
		_use(run, entity, slot)
	var started: TimedAction = actions.get(entity, null)
	if started != null:
		_advance(run, started, slot, bits)


## Picking up (§4.3): an item in touch range seen with identity or just felt; 1 s (Proposed).
func _start_pick_up(run: RunState, entity: int, item_entity: int) -> void:
	var h: HandsAndBelt = hands_of(entity)
	var item: Item = world.item_at(item_entity)
	if item == null or not _allowed(run, entity, &"interact") or not _allowed(run, entity, &"belt"):
		return
	if h.free_hand_blocked(&"pick_up"):
		return
	# MNR-16: a Hired Hand never picks up the revolver.
	if item.kind == ItemKinds.Kind.REVOLVER and ToolsParts.is_hand(run, entity):
		return
	if ItemKinds.hand_class(item.kind) == ItemKinds.HandClass.FREE_ONLY and h.free_hand != null:
		return
	var a: TimedAction = TimedAction.make(entity, &"pick_up", Tuning.f(&"lamp.pick_up_time" if ItemKinds.is_lamp(item.kind) else &"items.pick_up_time"),
		InputRecord.HOLD_INTERACT)
	a.target_entity = item_entity
	a.reach = Tuning.f(&"vision.touch_range_tiles")
	a.valid = func() -> bool: return world.items.has(item_entity)
	a.effect = func() -> void: _pick_up(run, entity, item_entity)
	start_action(run, a)


func _pick_up(run: RunState, entity: int, item_entity: int) -> void:
	var h: HandsAndBelt = hands_of(entity)
	var item: Item = world.item_at(item_entity)
	if item == null:
		return
	var at: Vector2 = run.registry.get_entity(item_entity).position
	if ItemKinds.hand_class(item.kind) == ItemKinds.HandClass.FREE_ONLY and h.free_hand != null:
		return
	if h.fits(item):
		world.lift(run, item_entity, &"pick_up", entity)
		h.store(item)
	else:
		# The belt is full: the selected slot's item is set down where the new one lay.
		var out: Item = h.take_slot(h.selected)
		if out == null:
			return
		world.lift(run, item_entity, &"pick_up", entity)
		h.store(item)
		world.put(run, out, at, &"swap_out", entity)
	changed.emit(entity)


## Setting down (Proposed order): the lamp hand's lamp or candle, then a can (or anything) in the
## free hand, then the selected belt item, onto the faced floor tile (else the miner's own), 1 s.
func _start_set_down(run: RunState, entity: int, slot: int) -> void:
	var h: HandsAndBelt = hands_of(entity)
	if h.two_handed or not _allowed(run, entity, &"belt"):
		return
	var item: Item = null
	var where: StringName = &""
	if h.lamp_hand != null and not h.hooked:
		item = h.lamp_hand
		where = &"lamp"
	elif h.free_hand != null:
		item = h.free_hand
		where = &"free"
	elif h.slots[h.selected] != null:
		item = h.slots[h.selected]
		where = &"slot"
	if item == null:
		return
	var tile: Vector2i = _faced_tile(run, entity, slot)
	var from_slot: int = h.selected
	var a: TimedAction = TimedAction.make(entity, &"set_down", Tuning.f(&"lamp.set_down_time" if ItemKinds.is_lamp(item.kind) else &"items.set_down_time"),
		InputRecord.HOLD_SET_DOWN)
	a.capability = &"belt"
	a.valid = func() -> bool: return _still_at(h, item, where, from_slot)
	a.effect = func() -> void:
		_remove(h, where, from_slot)
		world.put(run, item, Vector2(tile) + Vector2(0.5, 0.5), &"set_down", entity)
		changed.emit(entity)
	start_action(run, a)


func _still_at(h: HandsAndBelt, item: Item, where: StringName, slot: int) -> bool:
	match where:
		&"lamp":
			return h.lamp_hand == item and not h.hooked
		&"free":
			return h.free_hand == item
		_:
			return h.slots[slot] == item


func _remove(h: HandsAndBelt, where: StringName, slot: int) -> void:
	match where:
		&"lamp":
			h.lamp_hand = null
		&"free":
			h.free_hand = null
		_:
			h.slots[slot] = null


## The tile a set-down from `entity` (on `slot`) lands on: the faced tile, or its own if that is rock.
func faced_tile(run: RunState, entity: int, slot: int) -> Vector2i:
	return _faced_tile(run, entity, slot)


func _faced_tile(run: RunState, entity: int, slot: int) -> Vector2i:
	var me: SimEntity = run.registry.get_entity(entity)
	var u: PackedFloat64Array = LbDetMath.unit(float(run.movement.facing_of(slot)) / 65536.0)
	var ahead: Vector2 = me.position + Vector2(u[0], u[1])
	var tile: Vector2i = Vector2i(floori(ahead.x), floori(ahead.y))
	if run.mine != null and not run.mine.native.is_walkable(tile, false):
		return me.tile()
	return tile


## Use on the selected slot: a lamp there swaps with the lamp in hand (§4.3); any other kind goes
## to its owning ticket's handler.
func _use(run: RunState, entity: int, slot: int) -> void:
	var h: HandsAndBelt = hands_of(entity)
	var item: Item = h.slots[h.selected]
	# Both hands full (a carry): no kit, flare, revolver or anything else from the belt (§4.3).
	if item == null and not h.two_handed and empty_slot_use.is_valid() and _allowed(run, entity, &"belt"):
		empty_slot_use.call(run, entity, slot)
		return
	if item == null or h.two_handed or not _allowed(run, entity, &"belt"):
		return
	if ItemKinds.is_lamp(item.kind):
		# MNR-06 (Proposed): the swap takes lamp.slot_swap_time, the lamp going in shuttered first.
		if h.hooked or h.two_handed:
			return
		var from_slot: int = h.selected
		var a: TimedAction = TimedAction.make(entity, &"slot_swap", Tuning.f(&"lamp.slot_swap_time"), InputRecord.HOLD_USE)
		a.capability = &"belt"
		var in_hand: Item = h.lamp_hand
		a.valid = func() -> bool: return h.slots[from_slot] == item and h.lamp_hand == in_hand and not h.hooked
		a.effect = func() -> void:
			h.slots[from_slot] = in_hand
			h.lamp_hand = item
			changed.emit(entity)
		start_action(run, a)
	elif use_handlers.has(item.kind):
		var handler: Callable = use_handlers[item.kind]
		handler.call(run, entity, slot)


func _advance(run: RunState, a: TimedAction, slot: int, bits: int) -> void:
	var reason: StringName = _broken(run, a, slot, bits)
	if reason != &"":
		actions.erase(a.actor)
		a.cancel(reason)
		return
	a.ticks_done += 1
	if a.ticks_done >= a.ticks_needed:
		actions.erase(a.actor)
		a.finish()


func _broken(run: RunState, a: TimedAction, slot: int, bits: int) -> StringName:
	if _starved.has(slot):
		return TimedAction.STARVED
	if a.hold_bit != 0 and (bits & a.hold_bit) == 0:
		return TimedAction.RELEASED
	var all_partners: Array[int] = a.partners.duplicate()
	if a.partner != 0 and not all_partners.has(a.partner):
		all_partners.append(a.partner)
	for p: int in all_partners:
		var partner_slot: int = _slot_of(run, p)
		var reach: float = Tuning.f(&"vision.touch_range_tiles") + Tuning.f(&"items.range_tolerance")
		if partner_slot < 0 or (_holds(run, partner_slot) & a.hold_bit) == 0 \
				or run.registry.get_entity(p).position.distance_to(run.registry.get_entity(a.actor).position) > reach:
			a.let_go = p
			return TimedAction.PARTNER
	if run.miner_state != null and run.miner_state.miner(a.actor) != null and run.miner_state.life(a.actor) != a.life_at_start:
		return TimedAction.STATE
	if not _allowed(run, a.actor, a.capability):
		return TimedAction.STATE
	if a.needs_still and not run.movement.is_still(slot):
		return TimedAction.MOVED
	if a.needs_crouch and not run.movement.at_crouch_pace_or_slower(slot):
		return TimedAction.MOVED
	if a.valid.is_valid() and not Variants.flag(a.valid.call()):
		return TimedAction.TARGET
	if a.reach >= 0.0:
		var me: SimEntity = run.registry.get_entity(a.actor)
		var to: Vector2 = a.target_point
		if a.target_entity != 0:
			var t: SimEntity = run.registry.get_entity(a.target_entity)
			if t == null:
				return TimedAction.TARGET
			to = t.position
		if me.position.distance_to(to) > a.reach + Tuning.f(&"items.range_tolerance"):
			return TimedAction.RANGE
	return &""


func _slot_of(run: RunState, entity: int) -> int:
	for slot: int in run.movement.miner_slots():
		if run.movement.miner(slot).entity_id == entity:
			return slot
	return -1


func write_state(writer: SimStateWriter) -> void:
	world.write_state(writer)
	var ids: Array = hands.keys()
	ids.sort()
	for raw: Variant in ids:
		var h: HandsAndBelt = hands[raw]
		writer.put_i64(int(Variants.number(raw)))
		writer.put_i64(h.selected)
		for it: Item in h.held_items():
			writer.put_i64(it.uid)
			writer.put_i64(it.count)
	writer.put_i64(actions.size())
