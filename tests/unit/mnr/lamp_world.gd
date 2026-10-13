extends RefCounted
## Helpers for MNR-06's tests: a lit gauze lamp in a miner's hand, and each diagram state.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")


## A burning lamp (open, at `wick`) in the miner's lamp hand.
static func lit_in_hand(s: Scenario, h: MinerHandle, wick: int = LampRules.WICK_NORMAL) -> GauzeLamp:
	var at: Vector2 = s.run.registry.get_entity(h.entity_id).position
	var l: GauzeLamp = s.run.lamps.create(s.run, 1.0, 3, true, wick, at)
	assert(s.run.lamps.pick_up(s.run, l, h.entity_id))
	return l


## A lamp brought to a diagram state through the API (the miner holds it where that applies).
static func in_state(s: Scenario, h: MinerHandle, state: GauzeLamp.State) -> GauzeLamp:
	var run: RunState = s.run
	var lamps: LampSystem = run.lamps
	var l: GauzeLamp = lit_in_hand(s, h)
	var tile: Vector2i = run.registry.get_entity(h.entity_id).tile()
	match state:
		GauzeLamp.State.SHUTTERED:
			lamps.douse(run, l, 0)
		GauzeLamp.State.HOOKED:
			lamps.hook(run, l)
		GauzeLamp.State.HOOKED_SHUTTERED:
			lamps.hook(run, l)
			lamps.douse(run, l, 0)
		GauzeLamp.State.SLOTTED:
			lamps.douse(run, l, 0)
			lamps.slot(run, l)
		GauzeLamp.State.SET_DOWN_OPEN:
			lamps.set_down(run, l, tile)
		GauzeLamp.State.SET_DOWN_SHUTTERED:
			lamps.douse(run, l, 0)
			lamps.set_down(run, l, tile)
		GauzeLamp.State.CARRIED_OFF:
			lamps.take_by_moth(run, l, 999)
		GauzeLamp.State.OUT:
			lamps.snuff(run, l, "test")
		GauzeLamp.State.DRY:
			lamps.mark_dry(run, l)
		GauzeLamp.State.HOARDED:
			lamps.take_by_moth(run, l, 999)
			lamps.hoard(run, l, tile)
	return l


static func state_name(state: int) -> String:
	return str(GauzeLamp.State.find_key(state))
