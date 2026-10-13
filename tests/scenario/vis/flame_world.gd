extends RefCounted
## VIS-08 scenario helpers: a long hall, lamps lying lit, and a stand-in for CRT-14's Stythe tell.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")


static func hall(w: int = 60) -> FixtureMap:
	var rows: PackedStringArray = PackedStringArray(["#".repeat(w + 2)])
	for _y: int in 5:
		rows.append("#" + ".".repeat(w) + "#")
	rows.append("#".repeat(w + 2))
	return FixtureMap.from_ascii(rows)


static func lamp(s: Scenario, tile: Vector2i, wick: int = LampRules.WICK_NORMAL) -> GauzeLamp:
	return s.run.lamps.create(s.run, 1.0, 3, true, wick, Vector2(tile) + Vector2(0.5, 0.5))


## A stand-in Stythe whose tell gutters flames within stythe.tell_reach_tiles while `active[0]`.
static func stythe(s: Scenario, at: Vector2, active: Array[bool]) -> void:
	s.run.flame_states.causes.append(func(_run: RunState) -> Array:
		return [{"state": FlameFlags.GUTTER, "point": at, "reach": Tuning.f(&"stythe.tell_reach_tiles"), "cause": "stythe#1"}] if active[0] else [])


## The records a view holds within 0.1 tiles of `at`.
static func near(view: ReceivedView, at: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if view == null:
		return out
	for raw: Variant in view.entities.values():
		var e: Dictionary = Variants.dict(raw)
		var p: Vector2 = e["position"]
		if p.distance_to(at) < 0.1:
			out.append(e)
	return out
