extends RefCounted
## Helpers for CRT-04: an awake Moth, lit miners, and long roads to hunt along.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")


## A straight road one tile wide, `width` long, along y = 2.
static func road(width: int = 60) -> FixtureMap:
	return FixtureMap.from_ascii(PackedStringArray(["#".repeat(width), "#".repeat(width), "#" + ".".repeat(width - 2) + "#",
		"#".repeat(width), "#".repeat(width)]))


## An open hall, `w` x `h` inside.
static func hall(w: int = 40, h: int = 20) -> FixtureMap:
	var rows: PackedStringArray = PackedStringArray()
	rows.append("#".repeat(w + 2))
	for _y: int in h:
		rows.append("#" + ".".repeat(w) + "#")
	rows.append("#".repeat(w + 2))
	return FixtureMap.from_ascii(rows)


## The Moth placed at `at` and woken: into Frenzy (the waker unknown) or Prowl.
static func awake(s: Scenario, at: Vector2i, frenzy: bool = true) -> Moth:
	s.place_creature(WorldIds.EntityKind.MOTH, at)
	var m: Moth = s.run.creatures.creature_of_kind(WorldIds.EntityKind.MOTH)
	m.waker = {}
	m.enter(s.run, &"frenzy" if frenzy else &"prowl", "test")
	m.awake.begin(s.run, m, frenzy)
	return m


## A miner holding a burning lamp, open, at `wick`.
static func lit_miner(s: Scenario, name: String, at: Vector2i, wick: int = LampRules.WICK_NORMAL) -> MinerHandle:
	var h: MinerHandle = s.add_miner(name, at)
	h.at(0).lamp(false, wick)
	s.step(1)
	L.lit_in_hand(s, h, wick)
	return h


## Steps until the Moth is in `state_name` (or `limit` ticks); returns the ticks stepped, -1 if not.
static func until_state(s: Scenario, m: Moth, state_name: StringName, limit: int = 600) -> int:
	for i: int in limit:
		if m.state.name == state_name:
			return i
		s.step(1)
	return -1 if m.state.name != state_name else limit


static func life(s: Scenario, e: int) -> int:
	return s.run.miner_state.life(e)
