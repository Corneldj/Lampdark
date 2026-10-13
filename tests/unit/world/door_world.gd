extends RefCounted
## GEN-15 test helpers: a corridor with an air door in its middle, and a two-corridor variant.

const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")
const DOOR: Vector2i = Vector2i(15, 1)


## 30 tiles of corridor at y = 1, the door at x = 15.
static func corridor() -> FixtureMap:
	return FixtureMap.from_ascii(PackedStringArray(["#".repeat(32), "#" + ".".repeat(14) + "D" + ".".repeat(15) + "#", "#".repeat(32)]))


static func door(s: Object) -> AirDoorSystem.Door:
	var run: RunState = s.get(&"run")
	return run.air_doors.door_at(DOOR)
