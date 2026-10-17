extends RefCounted
## MOD-08's tests: SND-12's long road, humans with lit lamps in hand (scripted clients), and Hired
## Hands filling the places no client holds.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")
const W = preload("res://tests/unit/sound/signal_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")


static func road(length: int = 50, rib_at: int = 0) -> FixtureMap:
	return W.road(length, rib_at)


static func human(s: Scenario, name: String, tile: Vector2i, facing_deg: float = 0.0, lit: bool = true) -> MinerHandle:
	return W.miner(s, name, tile, facing_deg, lit)


## A filler Hand in place `slot` on `tile`; with `lamp`, a lit lamp turned down on its hook, as a
## Hand carries one it is handed.
static func hand(s: Scenario, tile: Vector2i, slot: int = 4, lamp: bool = false) -> int:
	var e: int = s.run.hands.fill_place(s.run, slot, Vector2(tile) + Vector2(0.5, 0.5))
	assert(e != 0, "the place is free")
	if lamp:
		var l: GauzeLamp = s.run.lamps.create(s.run, 1.0, 3, true, LampRules.WICK_DOWN, Vector2(tile) + Vector2(0.5, 0.5))
		assert(s.run.lamps.pick_up(s.run, l, e))
		assert(s.run.lamps.hook(s.run, l))
	return e


static func pos(s: Scenario, entity: int) -> Vector2:
	return s.run.registry.get_entity(entity).position


static func lamp_of(s: Scenario, entity: int) -> GauzeLamp:
	return s.run.lamps.lamp_in_hand(entity)


## The path distance in tiles between two entities, by CRT-02's walker paths.
static func path_tiles(s: Scenario, a: int, b: int) -> float:
	var r: Dictionary = s.run.creatures.nav.native.path(NavModes.Mode.WALKER, s.run.registry.get_entity(a).tile(),
		s.run.registry.get_entity(b).tile(), NavModes.defaults())
	var tiles: Array = Variants.array(r.get("tiles", []))
	var d: float = 0.0
	for i: int in range(1, tiles.size()):
		var p: Vector2i = tiles[i]
		var q: Vector2i = tiles[i - 1]
		d += Vector2(p - q).length()
	return d


static func h_of(s: Scenario, entity: int) -> HandController.Hand:
	return s.run.hands.hands[entity]
