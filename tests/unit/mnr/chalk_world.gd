extends RefCounted
## MNR-10's tests: a lit room (B's), a scripted miner, and wheel picks aimed at a chalk slice.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const B = preload("res://tests/unit/mnr/belt_world.gd")


static func miner(s: Scenario, name: String, tile: Vector2i, facing_deg: float = 0.0) -> MinerHandle:
	var h: MinerHandle = s.add_miner(name, tile, {"facing_deg": facing_deg})
	h.brain = null
	h.at(s.run.tick).face(facing_deg)
	return h


## The wheel angle (degrees, clockwise from east) at the centre of slice `index` of `count`.
static func slice_angle(index: int, count: int) -> float:
	return fposmod(index * 360.0 / count - 90.0, 360.0)


## Picks chalk mark `kind` from the C wheel now.
static func chalk(s: Scenario, h: MinerHandle, kind: int) -> void:
	h.at(s.run.tick).press(ActionRecord.Kind.CHALK, Intents.wheel_arg_distance(0.8), slice_angle(kind, ChalkMarks.COUNT))


## Steps until the mark appears or `ticks` pass; returns the ticks from the pick to the mark (-1).
static func ticks_to_mark(s: Scenario, ticks: int) -> int:
	var before: int = s.run.chalk.made.size()
	var start: int = s.run.tick
	for _i: int in ticks:
		s.step(1)
		if s.run.chalk.made.size() > before:
			return int(Variants.number(s.run.chalk.made[s.run.chalk.made.size() - 1]["tick"])) - start
	return -1
