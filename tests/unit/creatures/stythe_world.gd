extends RefCounted
## CRT-13's tests: the Stythe enabled (it is off in the starting tuning, held for M2), placed before
## anyone can see its tile, and lights planted exactly.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")

const ON: Dictionary = {"creatures.enabled": {"moth": 1, "tapper": 1, "stythe": 1}}


## A road `length` long on row 2 (rock above and below).
static func road(length: int) -> FixtureMap:
	var w: int = length + 2
	return FixtureMap.from_ascii(PackedStringArray(["#".repeat(w), "#".repeat(w), "#" + ".".repeat(length) + "#", "#".repeat(w), "#".repeat(w)]))


## The Stythe at `tile`, its lair at `lair` (default: far beyond reach, no territory or range).
static func stythe(s: Scenario, tile: Vector2i, lair: Vector2i = Vector2i(-5000, -5000)) -> StytheCreature:
	var id: int = s.place_creature(WorldIds.EntityKind.STYTHE, tile)
	assert(id != 0, "the Stythe placed")
	var st: StytheCreature = s.run.creatures.creature_of(id) as StytheCreature
	st.lair = lair
	st.senses.on_tiles_changed()
	return st


static func miner(s: Scenario, name: String, tile: Vector2i, facing_deg: float = 0.0) -> MinerHandle:
	var h: MinerHandle = s.add_miner(name, tile, {"facing_deg": facing_deg})
	h.brain = null
	h.at(s.run.tick).face(facing_deg)
	return h


## One tile lit to exactly `value` from now on.
static func light(s: Scenario, tile: Vector2i, value: float) -> int:
	return s.run.light.grid.add_spot(0, tile, value, 0)


static func pull(st: StytheCreature, values: Dictionary) -> void:
	st.system.gate.pull_of = func(m: int) -> float: return float(Variants.number(values.get(m, 0.0)))
