extends RefCounted
## Helpers for DIR-05: a hall with spots a-f, providers standing in for LFT-01 (who is inside a
## sealed base camp) and MOD-08 (who is a Hand), set per test.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")


static func hall() -> FixtureMap:
	return FixtureMap.from_ascii(PackedStringArray(["##########", "#a.b.c.d.#", "#........#", "#e.f.g.h.#", "##########"]))


## Adds named miners; returns their entity ids in order.
static func crew(s: Scenario, names: Array[String]) -> Array[int]:
	var spots: Array[String] = ["a", "b", "c", "d", "e", "f", "g", "h"]
	var out: Array[int] = []
	for i: int in names.size():
		out.append(s.add_miner(names[i], s.fixture.spot(spots[i])).entity_id)
	return out


## Stand-in providers: entities in `sealed` are inside a sealed base camp, in `hands` are Hands.
static func providers(s: Scenario, sealed: Dictionary, hands: Dictionary) -> void:
	s.run.crew.is_sealed_inside = func(e: int) -> bool: return sealed.has(e)
	s.run.crew.is_hand_driven = func(e: int) -> bool: return hands.has(e)


static func down(s: Scenario, e: int) -> void:
	s.run.miner_state.fall_unconscious(e, "test")
