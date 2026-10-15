extends RefCounted
## CRT-14's scenarios: a long dark road, the Stythe's lair far to the east (so a drag outlasts the
## victim's 20 s), the Stythe a little west of it, and Ann unlit to its west, marked by the Pull so
## it hunts her.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const W = preload("res://tests/unit/creatures/stythe_world.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")

var s: Scenario = null
var st: StytheCreature = null
var ann: MinerHandle = null
var pulls: Dictionary = {}


## `ann_x` west of the Stythe at `st_x`; the lair at `lair_x`.
func build(scn: Scenario, st_x: int = 40, ann_x: int = 37, lair_x: int = 95) -> void:
	s = scn
	st = W.stythe(s, Vector2i(st_x, 2), Vector2i(lair_x, 2))
	s.step(1)
	ann = W.miner(s, "ann", Vector2i(ann_x, 2), 0.0)
	pulls[ann.entity_id] = 60.0
	st.system.gate.pull_of = func(m: int) -> float: return float(Variants.number(pulls.get(m, 0.0)))


static func road(length: int = 100) -> FixtureMap:
	return W.road(length)


## Steps until the Stythe is in `state` (false if not within `ticks`).
func until_state(state: StringName, ticks: int = 400) -> bool:
	return s.run_until(func(_sv: Variant) -> bool: return st.state.name == state, ticks)


func states_seen(ticks: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for _i: int in ticks:
		s.step(1)
		if out.is_empty() or out[out.size() - 1] != st.state.name:
			out.append(st.state.name)
	return out
