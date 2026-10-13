class_name LampOil
extends RefCounted
## MNR-07: oil (Gameplay §4.4, §10.7). Every burning gauze lamp spends oil each tick at its state's
## factor (LampRules.burn_factor) times the seam's drink of the ring its own tile lies in; a full
## fount (1.0) is lamp.fill_minutes at normal. At zero it goes Dry; any oil added makes it Out, and
## only a relight brings it back. Pouring (a flask, a can) and sharing are 3 s timed actions. Oil
## is silent and has no flame tell. Server-only: oil reaches only the holder's Check Lamp.


## One tick of burning for every lamp that burns.
static func tick(run: RunState, lamps: LampSystem) -> void:
	var per_tick: float = 1.0 / (Tuning.f(&"lamp.fill_minutes") * 60.0 * Tuning.f(&"net.tick_hz"))
	for uid: int in lamps.sorted_uids():
		var l: GauzeLamp = lamps.lamps[uid]
		if not l.burning():
			continue
		l.oil -= per_tick * LampRules.burn_factor(l.place, l.shutter_closed, l.wick) * drink(run, lamps, l)
		if l.oil <= 1e-9:
			l.oil = 0.0
			lamps.mark_dry(run, l)


## The seam's drink at the lamp's own tile (its holder's for a held lamp), §10.7.
static func drink(run: RunState, _lamps: LampSystem, l: GauzeLamp) -> float:
	var at: Vector2 = l.at
	if l.held() and run.registry.has(l.holder):
		at = run.registry.get_entity(l.holder).position
	return Tuning.by_ring(&"lamp.seam_drink_by_ring", clampi(WorldCoords.ring_of_point(at), 0, 4))


## A flask's or can's oil, in fills (a flask holds 1, a can lamp.can_fills).
static func oil_in(source: Item) -> float:
	if source.kind == ItemKinds.Kind.OIL_FLASK:
		return float(Variants.number(source.state.get("fill", 1.0)))
	if source.kind == ItemKinds.Kind.PARAFFIN_CAN:
		return float(Variants.number(source.state.get("fills", Tuning.i(&"lamp.can_fills"))))
	return 0.0


static func _take(source: Item, amount: float) -> void:
	if source.kind == ItemKinds.Kind.OIL_FLASK:
		source.state["fill"] = maxf(0.0, oil_in(source) - amount)
	else:
		source.state["fills"] = maxf(0.0, oil_in(source) - amount)


## Pours from a flask (lamp.flask_pour_time) or a can (lamp.can_fill_time) into a gauze lamp in
## touch range, held or not, standing still: it tops the lamp up and the source keeps the rest
## (Proposed). A dry lamp given oil is Out.
static func pour_action(run: RunState, miner: int, source: Item, l: GauzeLamp, hold_bit: int = InputRecord.HOLD_USE) -> TimedAction:
	var seconds: float = Tuning.f(&"lamp.flask_pour_time" if source.kind == ItemKinds.Kind.OIL_FLASK else &"lamp.can_fill_time")
	var a: TimedAction = TimedAction.make(miner, &"pour_oil", seconds, hold_bit)
	a.needs_still = true
	a.capability = &"belt"
	_reach_lamp(run, a, l)
	a.valid = func() -> bool: return oil_in(source) > 0.0 and l.oil < 1.0 - 1e-9 and l.phase != LampRules.Phase.HOARDED \
		and l.place != LampRules.Place.MOTH
	a.effect = func() -> void:
		var amount: float = minf(1.0 - l.oil, oil_in(source))
		_take(source, amount)
		_add(run, l, amount)
	return a


## A can tops a flask up (lamp.can_fill_time).
static func fill_flask_action(_run: RunState, miner: int, can: Item, flask: Item, hold_bit: int = InputRecord.HOLD_USE) -> TimedAction:
	var a: TimedAction = TimedAction.make(miner, &"fill_flask", Tuning.f(&"lamp.can_fill_time"), hold_bit)
	a.needs_still = true
	a.capability = &"belt"
	a.valid = func() -> bool: return oil_in(can) > 0.0 and oil_in(flask) < 1.0 - 1e-9
	a.effect = func() -> void:
		var amount: float = minf(1.0 - oil_in(flask), oil_in(can))
		_take(can, amount)
		flask.state["fill"] = oil_in(flask) + amount
	return a


## Sharing (MNR-05's ring): lamp.share_oil_time, both miners still and holding interact; the oil
## levels between the two founts.
static func share_action(run: RunState, a_miner: int, b_miner: int) -> TimedAction:
	var a: TimedAction = TimedAction.make(a_miner, &"share_oil", Tuning.f(&"lamp.share_oil_time"), InputRecord.HOLD_INTERACT)
	a.needs_still = true
	a.partner = b_miner
	a.target_entity = b_miner
	a.reach = Tuning.f(&"vision.touch_range_tiles")
	a.valid = func() -> bool:
		return run.lamps.lamp_in_hand(a_miner) != null and run.lamps.lamp_in_hand(b_miner) != null \
			and run.movement != null and _still(run, b_miner)
	a.effect = func() -> void:
		var la: GauzeLamp = run.lamps.lamp_in_hand(a_miner)
		var lb: GauzeLamp = run.lamps.lamp_in_hand(b_miner)
		var mean: float = (la.oil + lb.oil) / 2.0
		for l: GauzeLamp in [la, lb]:
			var was: float = l.oil
			l.oil = mean
			if was <= 0.0 and mean > 0.0 and l.phase == LampRules.Phase.DRY:
				run.lamps.oil_added(run, l)
			run.lamps.mirror(l)
	return a


## A found lamp (GEN-10): lamp.found_oil_range of oil, lamp.found_notches_range notches, unlit.
static func make_found_lamp(run: RunState, rng: LbRng, at: Vector2) -> GauzeLamp:
	var oil_range: Vector2 = Tuning.range_f(&"lamp.found_oil_range")
	var notch_range: Vector2 = Tuning.range_f(&"lamp.found_notches_range")
	var oil: float = oil_range.x + rng.unit_double() * (oil_range.y - oil_range.x)
	var notches: int = rng.range(roundi(notch_range.x), roundi(notch_range.y))
	return run.lamps.create(run, oil, notches, false, LampRules.WICK_NORMAL, at)


static func _add(run: RunState, l: GauzeLamp, amount: float) -> void:
	if amount <= 0.0:
		return
	l.oil = minf(1.0, l.oil + amount)
	if l.phase == LampRules.Phase.DRY:
		run.lamps.oil_added(run, l)
	run.lamps.mirror(l)


## Touch range to the lamp: its holder, or where it lies; none for the miner's own lamp.
static func _reach_lamp(_run: RunState, a: TimedAction, l: GauzeLamp) -> void:
	if l.held() and l.holder == a.actor:
		return
	a.reach = Tuning.f(&"vision.touch_range_tiles")
	if l.held():
		a.target_entity = l.holder
	else:
		a.target_point = l.at


static func _still(run: RunState, miner: int) -> bool:
	for slot: int in run.movement.miner_slots():
		if run.movement.miner(slot).entity_id == miner:
			return run.movement.is_still(slot)
	return false
