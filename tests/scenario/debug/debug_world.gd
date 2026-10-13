extends RefCounted
## FND-08 test helpers: a hall with rock in the middle, and console access.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")


## 30 x 9 open floor with a rock pillar at (10..12, 4..6).
static func hall() -> FixtureMap:
	var rows: PackedStringArray = PackedStringArray(["#".repeat(32)])
	for y: int in 9:
		var row: String = "#"
		for x: int in 30:
			row += "#" if x >= 9 and x <= 11 and y >= 3 and y <= 5 else "."
		rows.append(row + "#")
	rows.append("#".repeat(32))
	return FixtureMap.from_ascii(rows)


static func run_line(s: Scenario, line: String, issuer: int = -1) -> Dictionary:
	var debug: DebugServer = s.run.debug
	return debug.execute(s.run, line, issuer)
