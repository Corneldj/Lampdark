extends RefCounted
## Helpers for MNR-04's tests: a lit room, items laid in it, and a miner's hands and belt.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")


## A 14 x 7 room: 'a' on the left, 'b' to its right.
static func room() -> FixtureMap:
	return FixtureMap.from_ascii(PackedStringArray([
		"##############",
		"#............#",
		"#............#",
		"#..a....b....#",
		"#............#",
		"#............#",
		"##############"]))


## Every floor tile of the room at `value` (0.6 is base camp's level: identity for small things).
static func light(s: Scenario, value: float = 0.6) -> int:
	var tiles: Array = []
	for y: int in range(1, 6):
		for x: int in range(1, 13):
			tiles.append(Vector2i(x, y))
	return s.run.light.grid.add_area("emergency", LbLightGrid.COLOUR_WHITE, 0, value, tiles)


## Lays a new item of `kind` at a tile's centre; returns its entity.
static func put(s: Scenario, kind: ItemKinds.Kind, tile: Vector2i, count: int = 1) -> int:
	var w: ItemWorld = s.run.inventory.world
	return w.put(s.run, w.make(kind, count), Vector2(tile) + Vector2(0.5, 0.5))


static func belt(s: Scenario, entity: int) -> HandsAndBelt:
	return s.run.inventory.hands_of(entity)


## A free-standing belt and a uid source, for the pure bookkeeping tests.
static func bare(check: int = 7) -> HandsAndBelt:
	return HandsAndBelt.create(1, check)
