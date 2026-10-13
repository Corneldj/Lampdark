extends RefCounted
## Helpers for CRT-03: a road with the Moth's roost at (10, 2) and a miner far off, and ways to
## put exact light on the Moth.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")

const ROOST: Vector2i = Vector2i(10, 2)


static func road(width: int = 48) -> FixtureMap:
	return FixtureMap.from_ascii(PackedStringArray(["#".repeat(width), "#".repeat(width), "#" + ".".repeat(width - 2) + "#",
		"#".repeat(width), "#".repeat(width)]))


static func moth(s: Scenario) -> Moth:
	s.place_creature(WorldIds.EntityKind.MOTH, ROOST)
	var m: Moth = s.run.creatures.creature_of_kind(WorldIds.EntityKind.MOTH)
	return m


## Exactly `value` on the Moth's tile for `ticks` ticks (0: until removed).
static func light_on(s: Scenario, value: float, ticks: int = 0) -> int:
	return s.run.light.grid.add_spot(0, ROOST, value, ticks)


## Steps until the Moth leaves `state_name` (or `limit` ticks); returns ticks stepped.
static func until_not(s: Scenario, m: Moth, state_name: StringName, limit: int = 400) -> int:
	var n: int = 0
	while m.state.name == state_name and n < limit:
		s.step(1)
		n += 1
	return n
