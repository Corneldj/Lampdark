class_name LampRules
extends RefCounted
## MNR-06's pure lamp rules (Gameplay §4.3, §4.4, A.1), shared by the server's LampSystem and
## NET-05's prediction of the owner's own lamp: the radius by where the lamp is, its shutter and
## its wick; the burn factor (MNR-07 applies it); and the 0.2 s step's linear ramp.

## Where a lamp is: in the lamp hand, on the belt hook, in a belt slot, set down on a floor tile,
## hung on a hook, or carried off by the Moth.
enum Place { HAND = 0, HOOK = 1, SLOT = 2, FLOOR = 3, HUNG = 4, MOTH = 5 }
## Whether it burns: Out (snuffed, smothered), Dry (no oil) and Hoarded give no light, no flame.
enum Phase { BURNING = 0, OUT = 1, DRY = 2, HOARDED = 3 }

const WICK_DOWN: int = 0
const WICK_NORMAL: int = 1
const WICK_UP: int = 2


## The open radius of a wick step.
static func wick_radius(wick: int) -> float:
	match clampi(wick, WICK_DOWN, WICK_UP):
		WICK_DOWN:
			return Tuning.f(&"lamp.radius_wick_down")
		WICK_UP:
			return Tuning.f(&"lamp.radius_wick_up")
	return Tuning.f(&"lamp.radius_normal")


## A burning lamp's radius before modifiers (guttering, blackdamp).
static func radius(place: Place, shutter_closed: bool, wick: int) -> float:
	match place:
		Place.HAND, Place.FLOOR, Place.HUNG:
			return Tuning.f(&"lamp.radius_shuttered") if shutter_closed else wick_radius(wick)
		Place.HOOK:
			return Tuning.f(&"lamp.radius_shuttered") if shutter_closed else Tuning.f(&"lamp.hook_radius")
		Place.SLOT:
			return Tuning.f(&"lamp.radius_slotted")
	return 0.0


## The core (0.30 and above) of a radius: VIS-02's core fraction.
static func core(of_radius: float) -> float:
	return of_radius * Tuning.f(&"light.core_fraction")


## The oil burn factor (MNR-07): shuttered, slotted or hooked x0.5; open by wick.
static func burn_factor(place: Place, shutter_closed: bool, wick: int) -> float:
	if shutter_closed or place == Place.SLOT or place == Place.HOOK:
		return Tuning.f(&"lamp.burn_factor_closed")
	match clampi(wick, WICK_DOWN, WICK_UP):
		WICK_DOWN:
			return Tuning.f(&"lamp.burn_factor_wick_down")
		WICK_UP:
			return Tuning.f(&"lamp.burn_factor_wick_up")
	return Tuning.f(&"lamp.burn_factor_normal")


## The wanted lamp state's bits in InputRecord.desired: bit 0 shutter closed, bits 1-2 wick.
static func wanted_closed(desired: int) -> bool:
	return (desired & 1) != 0


static func wanted_wick(desired: int) -> int:
	return clampi((desired >> 1) & 3, WICK_DOWN, WICK_UP)


## The radius in the lamp hand for a wanted state (what NET-05 predicts).
static func hand_radius(desired: int) -> float:
	return radius(Place.HAND, wanted_closed(desired), wanted_wick(desired))


## Ticks a step takes: the shutter's lamp.shutter_time, a wick step's lamp.wick_step_time, the
## longer if both change at once (both 0.2 s: 4 ticks).
static func step_ticks(shutter: bool = true, wick: bool = false) -> int:
	var s: float = Tuning.f(&"lamp.shutter_time") if shutter or not wick else 0.0
	if wick:
		s = maxf(s, Tuning.f(&"lamp.wick_step_time"))
	return maxi(1, roundi(s * Tuning.f(&"net.tick_hz")))


## The pool `k` ticks into a step of `steps` ticks from `from` to `to`, linear.
static func ramp(from: float, to: float, k: int, steps: int) -> float:
	return lerpf(from, to, clampf(float(k) / maxi(steps, 1), 0.0, 1.0))
