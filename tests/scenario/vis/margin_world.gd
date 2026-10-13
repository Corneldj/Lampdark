extends RefCounted
## Helpers for VIS-04's scenarios: an open room, a miner facing east with her own lamp, and the
## frame's margin as sets.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")


## A 24 x 9 room, walls round it, with Ann's spot at (8, 4) and Bob's at (3, 1).
static func room() -> FixtureMap:
	var rows: PackedStringArray = PackedStringArray()
	rows.append("#".repeat(24))
	for y: int in 7:
		rows.append("#" + ".".repeat(22) + "#")
	rows.append("#".repeat(24))
	rows[4] = "#" + ".".repeat(7) + "a" + ".".repeat(14) + "#"
	rows[1] = "#.." + "b" + ".".repeat(19) + "#"
	return FixtureMap.from_ascii(rows)


static func lamp(s: Scenario, owner: int, at: Vector2, radius: float = 4.0) -> int:
	return s.run.light.grid.add_point("gauze_lamp", 1, owner, 0, radius, 1.0, at, 0)


static func margin_tiles(frame: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var t: Dictionary = Variants.dict(frame.get("margin_tiles", {}))
	var xs: PackedInt32Array = t.get("x", PackedInt32Array())
	var ys: PackedInt32Array = t.get("y", PackedInt32Array())
	for i: int in xs.size():
		out[Vector2i(xs[i], ys[i])] = true
	return out


static func margin_positions(frame: Dictionary) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var positions: PackedVector2Array = Variants.dict(frame.get("margin_tokens", {})).get("position", PackedVector2Array())
	for p: Vector2 in positions:
		out.append(p)
	return out


static func centre(t: Vector2i) -> Vector2:
	return Vector2(t) + Vector2(0.5, 0.5)
