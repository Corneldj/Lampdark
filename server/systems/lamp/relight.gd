class_name Relight
extends RefCounted
## MNR-07: the four ways an Out gauze lamp burns again (Gameplay §4.4), all through MNR-06's
## relight (open, at its old wick). A dry lamp needs oil first: none is offered on it.
## - Flint (hold R or X): lamp.flint_time at a crouch's pace or slower, the free hand needed;
##   one notch and a 9 np click; safe in firedamp. In blackdamp it clicks, spends nothing and the
##   lamp stays Out (HAZ-05 supplies `in_blackdamp`). Not offered with no notches. Proposed: only
##   the lamp in the miner's own hand or on their hook.
## - A candle: lamp.candle_relight_time, a lit candle within touch range of the lamp's holder; a
##   naked flame (HAZ-04).
## - Passed flame (MNR-05's ring): lamp.pass_flame_time, both miners holding interact, a burning
##   gauze lamp (open or shuttered) to an Out one; a naked flame.
## - The relighter (LFT-01, after Power): no notch, no noise.
## Notches never come back.

const FLINT: StringName = &"flint"
const CANDLE: StringName = &"candle"
const PASSED: StringName = &"passed_flame"
const RELIGHTER: StringName = &"relighter"


## Whether `method` may relight `l` now (the lamp Out, not Dry; a flint needs a notch).
static func offered(l: GauzeLamp, method: StringName) -> bool:
	if l == null or l.phase != LampRules.Phase.OUT or l.place == LampRules.Place.MOTH:
		return false
	return method != FLINT or l.notches > 0


## The relight itself, once its action completes. Returns whether the lamp burns.
static func relight(run: RunState, l: GauzeLamp, method: StringName, by: int) -> bool:
	if not offered(l, method):
		return false
	var at: Vector2i = _tile_of(run, l)
	if method == FLINT:
		run.noise.emit(NoiseTypes.Type.FLINT_CLICK, at, {"source": by})
		if Variants.flag(run.lamps.in_blackdamp.call(at)):
			run.lamps.log_relight(run, l, method, by, false)
			return false
		l.notches -= 1
	if not run.lamps.relight(run, l, str(method)):
		return false
	if method == CANDLE or method == PASSED:
		run.lamps.naked_flame.emit(at, str(method))
	run.lamps.log_relight(run, l, method, by, true)
	return true


## The flint: the lamp in the miner's hand or on their hook; held on the relight control.
static func flint_action(run: RunState, miner: int) -> TimedAction:
	var a: TimedAction = TimedAction.make(miner, &"flint", Tuning.f(&"lamp.flint_time"), InputRecord.HOLD_RELIGHT)
	a.needs_crouch = true
	a.capability = &"belt"
	a.valid = func() -> bool:
		return offered(run.lamps.lamp_in_hand(miner), FLINT) and not run.inventory.free_hand_blocked(miner, &"flint")
	a.effect = func() -> void: relight(run, run.lamps.lamp_in_hand(miner), FLINT, miner)
	return a


## A candle relight of the lamp held by `holder`, by `miner` (either may hold the candle).
static func candle_action(run: RunState, miner: int, holder: int) -> TimedAction:
	var a: TimedAction = TimedAction.make(miner, &"candle_relight", Tuning.f(&"lamp.candle_relight_time"), InputRecord.HOLD_INTERACT)
	a.target_entity = holder
	a.reach = Tuning.f(&"vision.touch_range_tiles")
	a.valid = func() -> bool:
		return offered(run.lamps.lamp_in_hand(holder), CANDLE) and lit_candle_near(run, holder)
	a.effect = func() -> void: relight(run, run.lamps.lamp_in_hand(holder), CANDLE, miner)
	return a


## Passing a flame: `giver` holds a burning gauze lamp, `taker` an Out one; both hold interact.
static func pass_flame_action(run: RunState, giver: int, taker: int) -> TimedAction:
	var a: TimedAction = TimedAction.make(giver, &"pass_flame", Tuning.f(&"lamp.pass_flame_time"), InputRecord.HOLD_INTERACT)
	a.partner = taker
	a.target_entity = taker
	a.reach = Tuning.f(&"vision.touch_range_tiles")
	a.valid = func() -> bool:
		var g: GauzeLamp = run.lamps.lamp_in_hand(giver)
		return g != null and g.burning() and offered(run.lamps.lamp_in_hand(taker), PASSED)
	a.effect = func() -> void: relight(run, run.lamps.lamp_in_hand(taker), PASSED, giver)
	return a


## A lit candle, held or set down, within touch range of `holder`.
static func lit_candle_near(run: RunState, holder: int) -> bool:
	var at: Vector2 = run.registry.get_entity(holder).position
	var reach: float = Tuning.f(&"vision.touch_range_tiles")
	for raw: Variant in run.inventory.world.items.keys():
		var it: Item = run.inventory.world.items[raw]
		if it.kind == ItemKinds.Kind.CANDLE and Variants.flag(it.state.get("lit", false)) \
				and run.registry.get_entity(int(Variants.number(raw))).position.distance_to(at) <= reach:
			return true
	for raw: Variant in run.inventory.hands.keys():
		var h: HandsAndBelt = run.inventory.hands[raw]
		if h.lamp_hand != null and h.lamp_hand.kind == ItemKinds.Kind.CANDLE and Variants.flag(h.lamp_hand.state.get("lit", false)) \
				and run.registry.has(h.owner) and run.registry.get_entity(h.owner).position.distance_to(at) <= reach:
			return true
	return false


static func _tile_of(run: RunState, l: GauzeLamp) -> Vector2i:
	if l.held() and run.registry.has(l.holder):
		return run.registry.get_entity(l.holder).tile()
	return Vector2i(floori(l.at.x), floori(l.at.y))
