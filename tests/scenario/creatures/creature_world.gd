extends RefCounted
## Helpers for CRT-01's scenarios: a 40 x 20 hall with a few pillars, Ann's spot at (5, 10).

const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")


static func hall() -> FixtureMap:
	var rows: PackedStringArray = PackedStringArray()
	rows.append("#".repeat(40))
	for y: int in 18:
		var row: String = "#" + ".".repeat(38) + "#"
		if y % 6 == 3:
			row = row.substr(0, 12) + "##" + row.substr(14, 12) + "##" + row.substr(28)
		rows.append(row)
	rows.append("#".repeat(40))
	rows[10] = rows[10].substr(0, 5) + "a" + rows[10].substr(6)
	return FixtureMap.from_ascii(rows)
