class_name LampSystem
extends SimSystem
## MNR-06 (stage MINERS, after the inventory): every gauze lamp's state machine and its light.
## Each tick it adopts new lamp items, follows each lamp to wherever MNR-04's inventory now holds
## it (a hand, the belt hook, a slot, a floor tile or a hook), applies the holder's shutter and wick
## presses (edges of InputRecord.desired's lamp bits) 4 ticks later with the pool ramping linearly
## across the step, then registers each burning lamp with VIS-02: a flame even at radius 0,
## `carried` with its holder or `unheld`. Every transition goes through GauzeLamp's diagram; a
## refused one is logged in `refused` (soaks check it stays empty). Server-only.

signal lamp_changed(lamp: GauzeLamp, what: StringName, cause: String)
## MNR-07: a candle or a passed flame relit a lamp: a naked flame at a tile (HAZ-04 reads it).
signal naked_flame(tile: Vector2i, cause: String)

const KIND: String = "gauze_lamp"

## uid -> GauzeLamp
var lamps: Dictionary = {}
## Hook tiles (timber hooks, base camp's lamp hook): one lamp per hook (Proposed).
var hooks: Dictionary = {}
## Refused transitions: {tick, uid, transition, state}.
var refused: Array[Dictionary] = []
## Every Out -> Burning and every shutter opening, with its cause (soak invariants).
var openings: Array[Dictionary] = []
## miner -> the lamp bits of its last input (presses are edges).
var _last_bits: Dictionary = {}
## MNR-07: (tile) -> bool, the tile is in blackdamp (HAZ-05 sets it). A flint there clicks only.
var in_blackdamp: Callable = func(_tile: Vector2i) -> bool: return false
## MNR-07's relights: {tick, uid, method, by, lit}.
var relights: Array[Dictionary] = []
## SND-12: (uid) -> bool, the lamp is dark this tick in a HELP signal's blink (radius 0, still burning).
var dark_now: Callable = func(_uid: int) -> bool: return false
## uid -> Item, for lamps the Moth carries (in no inventory meanwhile).
var _carried_off: Dictionary = {}
var _run: RunState = null


func stage() -> int:
	return StageTable.Stage.MINERS


func order() -> int:
	return 30


func system_name() -> String:
	return "lamps"


func bind(run: RunState) -> void:
	_run = run
	if run.diff_log != null:
		run.diff_log.items.advances[ItemKinds.Kind.GAUZE_LAMP] = advance_lying


## GEN-13: a lamp left lying while its cell was gone, advanced from one tick to another as if it
## had burned there all along (MNR-07's rate at its place, shutter and wick, and the seam's drink
## of its ring), Dry if that empties it. `state` carries its phase as "lamp_phase".
func advance_lying(state: Dictionary, at: Vector2, from_tick: int, to_tick: int) -> Variant:
	var lit: bool = Variants.flag(state.get("lit", false))
	var phase: int = int(Variants.number(state.get("lamp_phase", LampRules.Phase.BURNING if lit else LampRules.Phase.OUT)))
	if phase != LampRules.Phase.BURNING or to_tick <= from_tick:
		return state
	var tile: Vector2i = Vector2i(floori(at.x), floori(at.y))
	var place: LampRules.Place = LampRules.Place.HUNG if hooks.has(tile) else LampRules.Place.FLOOR
	var per_tick: float = 1.0 / (Tuning.f(&"lamp.fill_minutes") * 60.0 * Tuning.f(&"net.tick_hz"))
	var closed: bool = Variants.flag(state.get("shutter", false))
	var wick: int = int(Variants.number(state.get("wick", LampRules.WICK_NORMAL)))
	var rate: float = per_tick * LampRules.burn_factor(place, closed, wick) \
		* Tuning.by_ring(&"lamp.seam_drink_by_ring", clampi(WorldCoords.ring_of_point(at), 0, 4))
	var oil: float = float(Variants.number(state.get("oil", 1.0))) - rate * (to_tick - from_tick)
	if oil <= 1e-9:
		oil = 0.0
		state["lit"] = false
		state["lamp_phase"] = LampRules.Phase.DRY
	state["oil"] = oil
	return state


#region API

## A new lamp lying (or hung) at `at`: GEN-10's found lamps, LFT-01's first lamp (hung, Out).
func create(run: RunState, oil: float, notches: int, lit: bool, wick: int, at: Vector2, hung: bool = false) -> GauzeLamp:
	var item: Item = run.inventory.world.make(ItemKinds.Kind.GAUZE_LAMP, 1,
		{"oil": oil, "notches": notches, "lit": lit, "wick": wick, "shutter": false, "hung": hung})
	run.inventory.world.put(run, item, at)
	reconcile(run)
	return lamps[item.uid]


func lamp_of_item(item: Item) -> GauzeLamp:
	return lamps.get(item.uid, null) if item != null else null


## The lamp in a miner's lamp hand (or on its hook), or null.
func lamp_in_hand(miner: int) -> GauzeLamp:
	if _run == null or _run.inventory == null or not _run.inventory.hands.has(miner):
		return null
	var h: HandsAndBelt = _run.inventory.hands[miner]
	return lamp_of_item(h.lamp_hand)


## The lamp lying as a world item entity, or null.
func lamp_at_entity(entity: int) -> GauzeLamp:
	return lamp_of_item(_run.inventory.world.item_at(entity)) if _run != null else null


## Opens or closes the shutter: takes effect lamp.shutter_time later (a 4-tick step).
func shutter(run: RunState, l: GauzeLamp, open: bool, cause: String = "input") -> bool:
	var transition: StringName = &"shutter_open" if open else &"shutter_close"
	if not _check(run, l, transition):
		return false
	_request(run, l, not open, l.want_wick if l.pending else l.wick, cause)
	return true


## Steps the wick down (-1) or up (+1): takes effect lamp.wick_step_time later.
func step_wick(run: RunState, l: GauzeLamp, dir: int, cause: String = "input") -> bool:
	var from: int = l.want_wick if l.pending else l.wick
	var to: int = clampi(from + signi(dir), LampRules.WICK_DOWN, LampRules.WICK_UP)
	if to == from or not (l.place == LampRules.Place.HAND or l.place == LampRules.Place.HOOK):
		return false
	if not l.burning():
		l.wick = to
		_changed(l, &"wick", cause)
		return true
	_request(run, l, l.want_closed if l.pending else l.shutter_closed, to, cause)
	return true


## Sets a held lamp down on a floor tile (the timed part is MNR-04's set-down action).
func set_down(run: RunState, l: GauzeLamp, tile: Vector2i) -> bool:
	if l.burning() and not _check(run, l, &"set_down"):
		return false
	if not _take_out(run, l):
		return false
	run.inventory.world.put(run, l.item, Vector2(tile) + Vector2(0.5, 0.5), &"set_down", l.holder)
	reconcile(run)
	return true


## Hangs a held lamp on a hook tile (one lamp per hook).
func hang(run: RunState, l: GauzeLamp, hook_tile: Vector2i) -> bool:
	if not hooks.has(hook_tile) or _lamp_on_hook(hook_tile) != null:
		return false
	return set_down(run, l, hook_tile)


## Picks an unheld lamp up into a miner's hands (MNR-04's store rules). From the hoard this is
## the unhoard: an ordinary pick-up that leaves it Out (§7.2).
func pick_up(run: RunState, l: GauzeLamp, miner: int) -> bool:
	if l.held() or l.place == LampRules.Place.MOTH:
		return false
	if l.phase == LampRules.Phase.HOARDED:
		return unhoard(run, l, miner)
	if l.burning() and not _check(run, l, &"pick_up"):
		return false
	var entity: int = _entity_of(run, l)
	var h: HandsAndBelt = run.inventory.hands_of(miner)
	if entity == 0 or not h.fits(l.item):
		return false
	run.inventory.world.lift(run, entity, &"pick_up", miner)
	h.store(l.item)
	reconcile(run)
	return true


## A teammate shutters an unheld open lamp where it lies (the 1 s is shutter_in_place_action).
## Nothing opens a lamp in place.
func shutter_in_place(run: RunState, l: GauzeLamp, by: int) -> bool:
	if not _check(run, l, &"shutter_in_place"):
		return false
	_finish_step(l)
	l.shutter_closed = true
	_changed(l, &"shutter_in_place", "miner %d" % by)
	return true


## A douse (MNR-05's ring option): the holder's open lamp, in hand or on the hook, shuttered at
## once when the 1 s action completes. They can reopen it.
func douse(run: RunState, l: GauzeLamp, by: int) -> bool:
	if not _check(run, l, &"douse"):
		return false
	_finish_step(l)
	l.shutter_closed = true
	_changed(l, &"douse", "miner %d" % by)
	return true


func hook(run: RunState, l: GauzeLamp) -> bool:
	if l.place != LampRules.Place.HAND or (l.burning() and not _check(run, l, &"hook")):
		return false
	run.inventory.hook_lamp(l.holder)
	reconcile(run)
	return l.place == LampRules.Place.HOOK


func unhook(run: RunState, l: GauzeLamp) -> bool:
	if l.place != LampRules.Place.HOOK or (l.burning() and not _check(run, l, &"unhook")):
		return false
	run.inventory.unhook_lamp(l.holder)
	reconcile(run)
	return l.place == LampRules.Place.HAND


## The lamp hand's shuttered lamp into the first empty slot. (An open lamp put in a slot through
## the inventory is shuttered first: two diagram steps, Proposed.)
func slot(run: RunState, l: GauzeLamp) -> bool:
	if l.place != LampRules.Place.HAND or (l.burning() and not _check(run, l, &"slot")):
		return false
	var h: HandsAndBelt = run.inventory.hands_of(l.holder)
	var free: int = h.slots.find(null)
	if free < 0:
		return false
	h.lamp_hand = null
	h.slots[free] = l.item
	reconcile(run)
	return true


## A slotted lamp back to an empty lamp hand.
func unslot(run: RunState, l: GauzeLamp) -> bool:
	if l.place != LampRules.Place.SLOT or (l.burning() and not _check(run, l, &"unslot")):
		return false
	var h: HandsAndBelt = run.inventory.hands_of(l.holder)
	if h.lamp_hand != null:
		return false
	h.slots[h.slots.find(l.item)] = null
	h.lamp_hand = l.item
	reconcile(run)
	return true


## The Stythe's snuff, blackdamp, a smother or a hatching brood: Out wherever it is.
func snuff(run: RunState, l: GauzeLamp, cause: String) -> bool:
	if not _check(run, l, &"snuff"):
		return false
	_finish_step(l)
	l.phase = LampRules.Phase.OUT
	_changed(l, &"snuff", cause)
	return true


## MNR-07: the oil ran out.
func mark_dry(run: RunState, l: GauzeLamp) -> bool:
	if not _check(run, l, &"mark_dry"):
		return false
	_finish_step(l)
	l.phase = LampRules.Phase.DRY
	_changed(l, &"dry", "oil")
	return true


## MNR-07: oil poured into a dry lamp leaves it Out, ready to relight.
func oil_added(run: RunState, l: GauzeLamp) -> bool:
	if not _check(run, l, &"oil_added"):
		return false
	l.phase = LampRules.Phase.OUT
	_changed(l, &"oil", "oil")
	return true


## MNR-07 only (flint, candle, passed flame, relighter): Out to Burning, open at its old wick.
func relight(run: RunState, l: GauzeLamp, cause: String = "relight") -> bool:
	if not _check(run, l, &"relight"):
		return false
	l.phase = LampRules.Phase.BURNING
	l.shutter_closed = false
	openings.append({"tick": run.tick, "uid": l.uid, "what": &"relight", "cause": cause})
	_changed(l, &"relight", cause)
	return true


## CRT-04: smothered and carried off by the Moth: Out, with the Moth, in no inventory.
func take_by_moth(run: RunState, l: GauzeLamp, moth: int) -> bool:
	if not _check(run, l, &"take_by_moth"):
		return false
	_take_out(run, l)
	_finish_step(l)
	_carried_off[l.uid] = l.item
	l.phase = LampRules.Phase.OUT
	l.place = LampRules.Place.MOTH
	l.holder = moth
	_changed(l, &"taken", "moth %d" % moth)
	return true


## CRT-05: hung in the hoard.
func hoard(run: RunState, l: GauzeLamp, tile: Vector2i) -> bool:
	if not _check(run, l, &"hoard"):
		return false
	_carried_off.erase(l.uid)
	l.phase = LampRules.Phase.HOARDED
	l.holder = 0
	run.inventory.world.put(run, l.item, Vector2(tile) + Vector2(0.5, 0.5), &"hoard")
	reconcile(run)
	_changed(l, &"hoarded", "moth")
	return true


## CRT-05: dropped by a retreating Moth, Out where it falls.
func drop_snuffed(run: RunState, l: GauzeLamp, tile: Vector2i) -> bool:
	if not _check(run, l, &"drop_snuffed"):
		return false
	_carried_off.erase(l.uid)
	l.holder = 0
	run.inventory.world.put(run, l.item, Vector2(tile) + Vector2(0.5, 0.5), &"drop")
	reconcile(run)
	_changed(l, &"dropped", "moth")
	return true


## Taken back from the hoard (an ordinary 1 s pick-up that wakes nothing): Out, in the hand.
func unhoard(run: RunState, l: GauzeLamp, miner: int) -> bool:
	if l.phase != LampRules.Phase.HOARDED:
		return false
	var entity: int = _entity_of(run, l)
	var h: HandsAndBelt = run.inventory.hands_of(miner)
	if entity == 0 or not h.fits(l.item):
		return false
	run.inventory.world.lift(run, entity, &"pick_up", miner)
	h.store(l.item)
	reconcile(run)
	return true


## RSC-01, CRT-09: a held lamp drops where its holder is, keeping its shutter and its flame.
func drop(run: RunState, l: GauzeLamp, tile: Vector2i) -> bool:
	if l.place != LampRules.Place.HAND and l.place != LampRules.Place.HOOK:
		return false
	var by: int = l.holder
	run.inventory.hands_of(by).hooked = false
	if not _take_out(run, l):
		return false
	_finish_step(l)
	run.inventory.world.put(run, l.item, Vector2(tile) + Vector2(0.5, 0.5), &"drop", by)
	reconcile(run)
	_changed(l, &"dropped", "miner %d" % by)
	return true


## CRT-09's Tapper.drop_lamp: a pin ran out, and the victim's lamp falls at the wall.
func drop_at_wall(victim: int, _face: Vector2i) -> void:
	var l: GauzeLamp = lamp_in_hand(victim)
	var e: SimEntity = _run.registry.get_entity(victim) if _run != null else null
	if l != null and e != null:
		drop(_run, l, e.tile())


## MNR-05's douse: a 1 s action on a teammate in touch range whose lamp is open.
func douse_action(run: RunState, actor: int, target: int) -> TimedAction:
	var a: TimedAction = TimedAction.make(actor, &"douse", Tuning.f(&"lamp.douse_time"), InputRecord.HOLD_INTERACT)
	a.target_entity = target
	a.reach = Tuning.f(&"vision.touch_range_tiles")
	a.valid = func() -> bool:
		var l: GauzeLamp = lamp_in_hand(target)
		return l != null and l.allows(&"douse")
	a.effect = func() -> void: douse(run, lamp_in_hand(target), actor)
	return a


## Shuttering an unheld open lamp in place: 1 s in touch range.
func shutter_in_place_action(run: RunState, actor: int, lamp_entity: int) -> TimedAction:
	var a: TimedAction = TimedAction.make(actor, &"shutter_in_place", Tuning.f(&"lamp.douse_time"), InputRecord.HOLD_INTERACT)
	a.target_entity = lamp_entity
	a.reach = Tuning.f(&"vision.touch_range_tiles")
	a.valid = func() -> bool:
		var l: GauzeLamp = lamp_at_entity(lamp_entity)
		return l != null and l.allows(&"shutter_in_place")
	a.effect = func() -> void: shutter_in_place(run, lamp_at_entity(lamp_entity), actor)
	return a


## For the Inquiry (CRT-03's moth_stir log): a miner's lamp state and wick, or {}.
func describe(miner: int) -> Dictionary:
	var l: GauzeLamp = lamp_in_hand(miner)
	if l == null:
		return {}
	return {"state": str(GauzeLamp.State.find_key(l.state())).to_lower(), "wick": l.wick}

#endregion


func tick(run: RunState) -> void:
	_run = run
	reconcile(run)
	_presses(run)
	_flint_presses(run)
	for uid: int in _sorted_uids():
		var l: GauzeLamp = lamps[uid]
		if l.pending and run.tick >= l.due_tick:
			_complete(l)
	LampOil.tick(run, self)
	_register(run)


## MNR-07: the relight control held, fresh, with the own lamp Out: a flint action starts.
func _flint_presses(run: RunState) -> void:
	if run.movement == null or run.inventory == null:
		return
	for miner_slot: int in run.movement.miner_slots():
		var m: int = run.movement.miner(miner_slot).entity_id
		var c: InputBuffer.Consumed = run.input_for(miner_slot)
		if c == null or not run.inventory.is_fresh(m, c.record.holds, InputRecord.HOLD_RELIGHT):
			continue
		run.inventory.mark_spent(m, InputRecord.HOLD_RELIGHT)
		if Relight.offered(lamp_in_hand(m), Relight.FLINT) and not run.inventory.free_hand_blocked(m, &"flint"):
			run.inventory.start_action(run, Relight.flint_action(run, m))


## MNR-07's Check Lamp record for the holder, while the control is held: the lamp in hand (or on
## the hook) as oil in 48ths of a fill and notches; {} with no gauze lamp.
func check_record(miner: int) -> Dictionary:
	var l: GauzeLamp = lamp_in_hand(miner)
	if l == null:
		return {}
	return {"oil48": clampi(roundi(l.oil * 48.0), 0, 48), "notches": l.notches}


func log_relight(run: RunState, l: GauzeLamp, method: StringName, by: int, lit: bool) -> void:
	relights.append({"tick": run.tick, "uid": l.uid, "method": method, "by": by, "lit": lit})


func sorted_uids() -> Array[int]:
	return _sorted_uids()


func mirror(l: GauzeLamp) -> void:
	_mirror(l)


## Follows every lamp item to where the inventory holds it now, applying the diagram's moves.
func reconcile(run: RunState) -> void:
	if run.inventory == null:
		return
	var seen: Dictionary = {}
	var inv: InventorySystem = run.inventory
	var miners: Array = inv.hands.keys()
	miners.sort()
	for raw: Variant in miners:
		var m: int = int(Variants.number(raw))
		var h: HandsAndBelt = inv.hands[raw]
		if _is_lamp(h.lamp_hand):
			_follow(run, h.lamp_hand, LampRules.Place.HOOK if h.hooked else LampRules.Place.HAND, m, Vector2.ZERO)
			seen[h.lamp_hand.uid] = true
		for it: Item in h.slots:
			if _is_lamp(it):
				_follow(run, it, LampRules.Place.SLOT, m, Vector2.ZERO)
				seen[it.uid] = true
	var ids: Array = inv.world.items.keys()
	ids.sort()
	var hung_on: Dictionary = {}
	for raw: Variant in ids:
		var it: Item = inv.world.items[raw]
		if not _is_lamp(it):
			continue
		var e: SimEntity = run.registry.get_entity(int(Variants.number(raw)))
		var tile: Vector2i = e.tile()
		# A lamp created hung (LFT-01's first lamp) brings its hook with it.
		if not lamps.has(it.uid) and Variants.flag(it.state.get("hung", false)):
			hooks[tile] = true
		var hung: bool = hooks.has(tile) and not hung_on.has(tile)
		if hung:
			hung_on[tile] = true
		_follow(run, it, LampRules.Place.HUNG if hung else LampRules.Place.FLOOR, 0, e.position)
		seen[it.uid] = true
	for uid: int in _sorted_uids():
		if not seen.has(uid) and not _carried_off.has(uid):
			var gone: GauzeLamp = lamps[uid]
			_remove_source(run, gone)
			lamps.erase(uid)


func _follow(run: RunState, it: Item, place: LampRules.Place, holder: int, at: Vector2) -> void:
	var l: GauzeLamp = lamps.get(it.uid, null)
	if l == null:
		l = _adopt(it, place, holder, at)
		return
	if l.place == place and l.holder == holder:
		l.at = at
		return
	_finish_step(l)
	var was_hoarded: bool = l.phase == LampRules.Phase.HOARDED
	if not l.burning():
		if was_hoarded and (place == LampRules.Place.HAND or place == LampRules.Place.SLOT or place == LampRules.Place.HOOK):
			_apply(run, l, &"unhoard")
		l.place = place
		l.holder = holder
		l.at = at
		if place == LampRules.Place.SLOT:
			l.shutter_closed = true
		return
	# Burning: through the hand. Off the floor or hook is a pick-up; off the belt hook an unhook;
	# out of a slot an unslot; then on to where it is now.
	match l.place:
		LampRules.Place.FLOOR, LampRules.Place.HUNG:
			if place == LampRules.Place.FLOOR or place == LampRules.Place.HUNG:
				l.place = place
				l.at = at
				return
			_apply(run, l, &"pick_up")
		LampRules.Place.HOOK:
			_apply(run, l, &"unhook")
		LampRules.Place.SLOT:
			_apply(run, l, &"unslot")
	l.holder = holder
	l.at = at
	match place:
		LampRules.Place.HOOK:
			_apply(run, l, &"hook")
		LampRules.Place.SLOT:
			if not l.shutter_closed:
				_apply(run, l, &"shutter_close")
			_apply(run, l, &"slot")
		LampRules.Place.FLOOR, LampRules.Place.HUNG:
			_apply(run, l, &"set_down")
			l.place = place
	l.holder = holder


## Applies one diagram transition's effect on place and shutter (validated).
func _apply(run: RunState, l: GauzeLamp, transition: StringName) -> void:
	if not _check(run, l, transition):
		return
	match transition:
		&"pick_up", &"unhook", &"unslot":
			l.place = LampRules.Place.HAND
		&"hook":
			l.place = LampRules.Place.HOOK
		&"slot":
			l.place = LampRules.Place.SLOT
		&"set_down":
			l.place = LampRules.Place.FLOOR
			l.holder = 0
		&"shutter_close":
			l.shutter_closed = true
		&"unhoard":
			l.phase = LampRules.Phase.OUT
	_changed(l, transition, "inventory")


func _adopt(it: Item, place: LampRules.Place, holder: int, at: Vector2) -> GauzeLamp:
	var l: GauzeLamp = GauzeLamp.new()
	l.uid = it.uid
	l.item = it
	l.place = place
	l.holder = holder
	l.at = at
	l.phase = LampRules.Phase.BURNING if Variants.flag(it.state.get("lit", false)) else LampRules.Phase.OUT
	l.wick = int(Variants.number(it.state.get("wick", LampRules.WICK_NORMAL)))
	l.shutter_closed = Variants.flag(it.state.get("shutter", false)) or place == LampRules.Place.SLOT
	l.oil = float(Variants.number(it.state.get("oil", it.state.get("fills", 1))))
	l.notches = int(Variants.number(it.state.get("notches", Tuning.i(&"lamp.max_notches"))))
	# GEN-13: a lamp put back by a replay keeps its phase (Dry, Hoarded).
	if it.state.has("restore_phase"):
		l.phase = int(Variants.number(it.state["restore_phase"])) as LampRules.Phase
		it.state.erase("restore_phase")
	lamps[l.uid] = l
	_mirror(l)
	return l


## The holders' shutter and wick presses: edges of their input's lamp bits.
func _presses(run: RunState) -> void:
	if run.movement == null:
		return
	var by_entity: Dictionary = {}
	for miner_slot: int in run.movement.miner_slots():
		by_entity[run.movement.miner(miner_slot).entity_id] = miner_slot
	var miners: Array = by_entity.keys()
	miners.sort()
	for raw: Variant in miners:
		var m: int = int(Variants.number(raw))
		var c: InputBuffer.Consumed = run.input_for(int(Variants.number(by_entity[raw])))
		if c == null:
			continue
		var bits: int = c.record.desired & InputRecord.DESIRED_LAMP_MASK
		var last: int = int(Variants.number(_last_bits.get(m, bits)))
		_last_bits[m] = bits
		if bits == last:
			continue
		var l: GauzeLamp = lamp_in_hand(m)
		if l == null or (run.miner_state != null and run.miner_state.miner(m) != null
				and not Variants.flag(run.miner_state.capabilities(m)["lamp"])):
			continue
		if LampRules.wanted_closed(bits) != LampRules.wanted_closed(last):
			shutter(run, l, not LampRules.wanted_closed(bits))
		var dw: int = LampRules.wanted_wick(bits) - LampRules.wanted_wick(last)
		if dw != 0:
			step_wick(run, l, dw)


func _request(run: RunState, l: GauzeLamp, closed: bool, wick: int, cause: String) -> void:
	var from: float = l.radius_now(run.tick)
	var shutter_moves: bool = closed != (l.want_closed if l.pending else l.shutter_closed)
	var wick_moves: bool = wick != (l.want_wick if l.pending else l.wick)
	l.want_closed = closed
	l.want_wick = wick
	l.pending = true
	l.press_tick = run.tick
	l.ramp_steps = LampRules.step_ticks(shutter_moves or not wick_moves, wick_moves)
	l.due_tick = run.tick + l.ramp_steps
	l.ramp_from = from
	l.ramp_to = LampRules.radius(l.place, closed, wick)
	if not closed and l.shutter_closed:
		openings.append({"tick": run.tick, "uid": l.uid, "what": &"open", "cause": cause, "holder": l.holder})
	_changed(l, &"step_pressed", cause)


func _complete(l: GauzeLamp) -> void:
	var what: StringName = &"shutter" if l.want_closed != l.shutter_closed else &"wick"
	l.shutter_closed = l.want_closed
	l.wick = l.want_wick
	l.pending = false
	_changed(l, what, "step done at %d (pressed %d)" % [l.due_tick, l.press_tick])


## A step in progress lands at once (the lamp moved, was snuffed or doused).
func _finish_step(l: GauzeLamp) -> void:
	if l.pending:
		l.shutter_closed = l.want_closed
		l.wick = l.want_wick
		l.pending = false


func _register(run: RunState) -> void:
	if run.light == null:
		return
	for uid: int in _sorted_uids():
		var l: GauzeLamp = lamps[uid]
		if not l.burning():
			_remove_source(run, l)
			continue
		var holder_entity: SimEntity = run.registry.get_entity(l.holder) if l.held() else null
		var pos: Vector2 = holder_entity.position if holder_entity != null else l.at
		var owner: int = l.holder if l.held() else 0
		var flags: int = LbLightGrid.FLAG_FLAME | (LbLightGrid.FLAG_CARRIED if l.held() else LbLightGrid.FLAG_UNHELD)
		var r: float = 0.0 if Variants.flag(dark_now.call(l.uid)) else l.radius_now(run.tick)
		if l.source != 0 and l.source_owner != owner:
			_remove_source(run, l)
		if l.source == 0:
			l.source = run.light.grid.add_point(KIND, LbLightGrid.COLOUR_AMBER, owner, flags, r, 1.0, pos, 0)
			l.source_owner = owner
			l.source_flags = flags
		else:
			if flags != l.source_flags:
				run.light.grid.set_flags(l.source, flags)
				l.source_flags = flags
			run.light.grid.update_point(l.source, pos, r, 1.0)


func _remove_source(run: RunState, l: GauzeLamp) -> void:
	if l.source != 0 and run.light != null:
		run.light.grid.remove_source(l.source)
	l.source = 0
	l.source_owner = -1
	l.source_flags = -1


func _check(run: RunState, l: GauzeLamp, transition: StringName) -> bool:
	if l != null and l.allows(transition):
		return true
	refused.append({"tick": run.tick, "uid": l.uid if l != null else 0, "transition": transition,
		"state": str(GauzeLamp.State.find_key(l.state())) if l != null else "none"})
	return false


## Takes a lamp's item out of whichever hand, slot or floor holds it.
func _take_out(run: RunState, l: GauzeLamp) -> bool:
	var inv: InventorySystem = run.inventory
	if l.held() and inv.hands.has(l.holder):
		var h: HandsAndBelt = inv.hands[l.holder]
		if h.lamp_hand == l.item:
			h.lamp_hand = null
			h.hooked = false
			return true
		var i: int = h.slots.find(l.item)
		if i >= 0:
			h.slots[i] = null
			return true
		return false
	var entity: int = _entity_of(run, l)
	if entity == 0:
		return false
	inv.world.lift(run, entity, &"take")
	return true


func _entity_of(run: RunState, l: GauzeLamp) -> int:
	for raw: Variant in run.inventory.world.items.keys():
		if run.inventory.world.items[raw] == l.item:
			return int(Variants.number(raw))
	return 0


func _lamp_on_hook(tile: Vector2i) -> GauzeLamp:
	for uid: int in _sorted_uids():
		var l: GauzeLamp = lamps[uid]
		if l.place == LampRules.Place.HUNG and Vector2i(floori(l.at.x), floori(l.at.y)) == tile:
			return l
	return null


func _is_lamp(it: Item) -> bool:
	return it != null and it.kind == ItemKinds.Kind.GAUZE_LAMP


func _sorted_uids() -> Array[int]:
	var out: Array[int] = []
	for raw: Variant in lamps.keys():
		out.append(int(Variants.number(raw)))
	out.sort()
	return out


func _changed(l: GauzeLamp, what: StringName, cause: String) -> void:
	_mirror(l)
	lamp_changed.emit(l, what, cause)


## The item carries the lamp's state (the owner's InventoryWire reads shutter and wick).
func _mirror(l: GauzeLamp) -> void:
	l.item.state["lit"] = l.burning()
	l.item.state["shutter"] = l.shutter_closed
	l.item.state["wick"] = l.wick
	l.item.state["oil"] = l.oil
	l.item.state["notches"] = l.notches


func write_state(writer: SimStateWriter) -> void:
	for uid: int in _sorted_uids():
		var l: GauzeLamp = lamps[uid]
		writer.put_i64(uid)
		writer.put_i64(l.phase)
		writer.put_i64(l.place)
		writer.put_bool(l.shutter_closed)
		writer.put_i64(l.wick)
		writer.put_i64(l.holder)
		writer.put_bool(l.pending)
