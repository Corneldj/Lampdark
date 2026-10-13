extends RefCounted
## Helpers for VIS-03's scenarios: a lamp, an entity, and the frame as sets.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")


static func lamp(s: Scenario, at: Vector2, radius: float = 4.0, owner: int = 0) -> int:
	return s.run.light.grid.add_point("gauze_lamp", 1, owner, 0, radius, 1.0, at, 0)


static func tiles(frame: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var t: Dictionary = Variants.dict(frame.get("tiles", {}))
	var xs: PackedInt32Array = t.get("x", PackedInt32Array())
	var ys: PackedInt32Array = t.get("y", PackedInt32Array())
	for i: int in xs.size():
		out[Vector2i(xs[i], ys[i])] = true
	return out


static func token_count(frame: Dictionary) -> int:
	var sizes: PackedByteArray = Variants.dict(frame.get("tokens", {})).get("size", PackedByteArray())
	return sizes.size()


static func identified(frame: Dictionary) -> PackedInt64Array:
	return frame.get("identified", PackedInt64Array())
