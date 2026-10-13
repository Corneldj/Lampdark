extends RefCounted
## Helpers for RSC-03: a hall with miners, a stand-in creature, and the holds.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")

const L: int = MinerTransitions.Life.UPRIGHT


static func hall() -> FixtureMap:
	return FixtureMap.from_ascii(PackedStringArray(["############", "#a.b.c.....#", "#..........#", "############"]))


static func life(s: Scenario, e: int) -> int:
	return s.run.miner_state.life(e)


## Steps until the grab times out; returns ticks stepped (or -1 within `limit`).
static func ticks_to_timeout(s: Scenario, grab_id: int, limit: int) -> int:
	var hit: Array[int] = [-1]
	var n: Array[int] = [0]
	var on: Callable = func(id: int) -> void:
		if id == grab_id and hit[0] < 0:
			hit[0] = n[0]
	s.run.holds.grab_timed_out.connect(on)
	for i: int in limit:
		n[0] = i + 1
		s.step(1)
		if hit[0] >= 0:
			break
	s.run.holds.grab_timed_out.disconnect(on)
	return hit[0]
