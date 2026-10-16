extends RefCounted
## Helpers for DIR-01: a long hall with the Director on, and stand-in light and lamps for the
## Draught's own rows (vision still sees by the real light grid, so a creature is seen only where a
## real light falls on it). NEUTRAL light is neither dark (below 0.12) nor lit (0.30 or more), so
## only the row under test moves a value.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")

const NEUTRAL: float = 0.2


## A hall 42 tiles long, spots a-f along row 1 (x 1, 5, 11, 21, 31, 40) and g-h on row 3 (x 1, 3).
static func hall() -> FixtureMap:
	var rows: PackedStringArray = PackedStringArray(["#".repeat(44)])
	var top: String = "#" + ".".repeat(42) + "#"
	for spot: Array in [["a", 1], ["b", 5], ["c", 11], ["d", 21], ["e", 31], ["f", 40]]:
		var x: int = spot[1]
		top = top.substr(0, x) + str(spot[0]) + top.substr(x + 1)
	rows.append(top)
	rows.append("#" + ".".repeat(42) + "#")
	var low: String = "#" + ".".repeat(42) + "#"
	low = low.substr(0, 1) + "g" + low.substr(2)
	low = low.substr(0, 3) + "h" + low.substr(4)
	rows.append(low)
	rows.append("#".repeat(44))
	return FixtureMap.from_ascii(rows)


## Named miners at spots, in order; returns their entity ids.
static func crew(s: Scenario, names: Array[String], spots: Array[String]) -> Array[int]:
	var out: Array[int] = []
	for i: int in names.size():
		out.append(s.add_miner(names[i], s.fixture.spot(spots[i])).entity_id)
	return out


## Neutral light everywhere and no lamp lit in hand, except as given: light by miner entity.
static func stand_in(s: Scenario, light_by_miner: Dictionary = {}, lamps: Dictionary = {}) -> void:
	s.run.draught.light_at = func(tile: Vector2i) -> float:
		for raw: Variant in light_by_miner.keys():
			var e: SimEntity = s.run.registry.get_entity(int(Variants.number(raw)))
			if e != null and WorldCoords.tile_at(e.position) == tile:
				return float(Variants.number(light_by_miner[raw]))
		return NEUTRAL
	s.run.draught.lit_lamp_in_hand = func(e: int) -> bool: return lamps.has(e)


static func value(s: Scenario, e: int) -> float:
	return s.run.draught.intensity_of(e)


## Sets a tracked miner's value (the Draught must have ticked once since they joined).
static func set_value(s: Scenario, e: int, v: float) -> void:
	assert(s.run.draught.set_intensity(e, v), "miner %d is tracked" % e)


## Forces the cycle into a long RELAX, or back to BUILD (the cycle itself is DIR-01's to test).
static func force_relax(s: Scenario, on: bool) -> void:
	s.run.draught.cycle.phase = DraughtCycle.Phase.RELAX if on else DraughtCycle.Phase.BUILD
	s.run.draught.cycle.left = 100000 if on else 0
