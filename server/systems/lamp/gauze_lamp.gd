class_name GauzeLamp
extends RefCounted
## MNR-06: one gauze safety lamp's state (Gameplay §4.4): its phase (Burning, Out, Dry,
## Hoarded), where it is, its shutter and wick, its oil and notches (MNR-07 spends them), and the
## step in progress. The lamp item (MNR-04's Item, kind GAUZE_LAMP) is its body: the inventory
## says whose hand, slot or floor tile holds it, and LampSystem follows. `allows()` is the §4.4
## state diagram; every transition goes through it. Server-only: oil and notches reach only the
## holder's Check Lamp (MNR-07).

## The diagram's states, by phase, place and shutter.
enum State { OPEN, SHUTTERED, HOOKED, HOOKED_SHUTTERED, SLOTTED, SET_DOWN_OPEN, SET_DOWN_SHUTTERED, CARRIED_OFF, OUT, DRY, HOARDED }

## The transitions the diagram allows: transition -> {from state: to state}. Location moves of a
## lamp that is not burning (Out or Dry, held, slotted or lying anywhere) are free: they change no
## light. Hooked shuttered (Proposed) mirrors Hooked.
const DIAGRAM: Dictionary = {
	&"shutter_close": {State.OPEN: State.SHUTTERED, State.HOOKED: State.HOOKED_SHUTTERED},
	&"shutter_open": {State.SHUTTERED: State.OPEN, State.HOOKED_SHUTTERED: State.HOOKED},
	&"douse": {State.OPEN: State.SHUTTERED, State.HOOKED: State.HOOKED_SHUTTERED},
	&"hook": {State.OPEN: State.HOOKED, State.SHUTTERED: State.HOOKED_SHUTTERED},
	&"unhook": {State.HOOKED: State.OPEN, State.HOOKED_SHUTTERED: State.SHUTTERED},
	&"slot": {State.SHUTTERED: State.SLOTTED},
	&"unslot": {State.SLOTTED: State.SHUTTERED},
	&"set_down": {State.OPEN: State.SET_DOWN_OPEN, State.SHUTTERED: State.SET_DOWN_SHUTTERED},
	&"shutter_in_place": {State.SET_DOWN_OPEN: State.SET_DOWN_SHUTTERED},
	&"pick_up": {State.SET_DOWN_OPEN: State.OPEN, State.SET_DOWN_SHUTTERED: State.SHUTTERED},
	&"snuff": {State.OPEN: State.OUT, State.SHUTTERED: State.OUT, State.HOOKED: State.OUT, State.HOOKED_SHUTTERED: State.OUT,
		State.SLOTTED: State.OUT, State.SET_DOWN_OPEN: State.OUT, State.SET_DOWN_SHUTTERED: State.OUT},
	&"mark_dry": {State.OPEN: State.DRY, State.SHUTTERED: State.DRY, State.HOOKED: State.DRY, State.HOOKED_SHUTTERED: State.DRY,
		State.SLOTTED: State.DRY, State.SET_DOWN_OPEN: State.DRY, State.SET_DOWN_SHUTTERED: State.DRY},
	&"take_by_moth": {State.OPEN: State.CARRIED_OFF, State.SHUTTERED: State.CARRIED_OFF, State.HOOKED: State.CARRIED_OFF,
		State.HOOKED_SHUTTERED: State.CARRIED_OFF, State.SET_DOWN_OPEN: State.CARRIED_OFF, State.SET_DOWN_SHUTTERED: State.CARRIED_OFF},
	&"hoard": {State.CARRIED_OFF: State.HOARDED},
	&"drop_snuffed": {State.CARRIED_OFF: State.OUT},
	&"unhoard": {State.HOARDED: State.OUT},
	&"oil_added": {State.DRY: State.OUT},
	&"relight": {State.OUT: State.OPEN},
}

var uid: int = 0
var item: Item = null
var phase: LampRules.Phase = LampRules.Phase.OUT
var place: LampRules.Place = LampRules.Place.FLOOR
var shutter_closed: bool = false
var wick: int = LampRules.WICK_NORMAL
## The miner (or Moth) holding it, 0 when unheld.
var holder: int = 0
## Where it lies or hangs, while unheld.
var at: Vector2 = Vector2.ZERO
## Oil as a fraction of a full fount, and flint notches (MNR-07's).
var oil: float = 1.0
var notches: int = 3
## A shutter or wick step in progress: the wanted state, its press and completion ticks, and the
## pool's ramp across it.
var pending: bool = false
var want_closed: bool = false
var want_wick: int = LampRules.WICK_NORMAL
var press_tick: int = -1
var due_tick: int = -1
var ramp_from: float = 0.0
var ramp_to: float = 0.0
var ramp_steps: int = 4
## VIS-02's source while it burns, its owner and flags as registered.
var source: int = 0
var source_owner: int = -1
var source_flags: int = -1


## The diagram state now.
func state() -> State:
	match phase:
		LampRules.Phase.OUT:
			return State.CARRIED_OFF if place == LampRules.Place.MOTH else State.OUT
		LampRules.Phase.DRY:
			return State.DRY
		LampRules.Phase.HOARDED:
			return State.HOARDED
	match place:
		LampRules.Place.HOOK:
			return State.HOOKED_SHUTTERED if shutter_closed else State.HOOKED
		LampRules.Place.SLOT:
			return State.SLOTTED
		LampRules.Place.FLOOR, LampRules.Place.HUNG:
			return State.SET_DOWN_SHUTTERED if shutter_closed else State.SET_DOWN_OPEN
	return State.SHUTTERED if shutter_closed else State.OPEN


func allows(transition: StringName) -> bool:
	return Variants.dict(DIAGRAM.get(transition, {})).has(state())


## The diagram state a transition leads to (or -1 if it is not allowed now).
func leads_to(transition: StringName) -> int:
	return int(Variants.number(Variants.dict(DIAGRAM.get(transition, {})).get(state(), -1)))


func burning() -> bool:
	return phase == LampRules.Phase.BURNING


func held() -> bool:
	return place == LampRules.Place.HAND or place == LampRules.Place.HOOK or place == LampRules.Place.SLOT


## The radius this tick: the step's ramp while one runs, else the state's.
func radius_now(now: int) -> float:
	if not burning():
		return 0.0
	if pending:
		return LampRules.ramp(ramp_from, ramp_to, now - press_tick, ramp_steps)
	return LampRules.radius(place, shutter_closed, wick)
