extends RefCounted
## RSC-04's scenarios: miners wandering the test map with their lamps (NET-07's record_world), one or
## more of them put down, and short coming-round spells so a test sees several windows.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const W = preload("res://tests/scenario/net/record_world.gd")

## A short spell for tests (the real one is 60-120 s).
const SHORT: Dictionary = {"rescue.coming_round_interval_s": [3.0, 5.0]}


static func fall(s: Scenario, h: MinerHandle) -> void:
	assert(s.run.falls.fall_unconscious(s.run, h.entity_id, FallCause.Cause.MOTH_SMOTHER))
	s.step(1)


static func fallen(s: Scenario, h: MinerHandle) -> DarkSystem.Fallen:
	return s.run.dark.fallen.get(h.entity_id, null)


## Steps until the miner's window opens; false if it does not within `ticks`.
static func until_window(s: Scenario, h: MinerHandle, ticks: int = 400) -> bool:
	return s.run_until(func(_sv: Variant) -> bool: return s.run.dark.in_window(h.entity_id), ticks)
