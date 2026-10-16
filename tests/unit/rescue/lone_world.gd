extends RefCounted
## RSC-09's worlds: a small room, a crew of `names` standing still, the lobby by mode, and stand-in
## Hands (MOD-08's, until it lands) by entity through the census's is_hand_driven.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const B = preload("res://tests/unit/mnr/belt_world.gd")
const TILES: Array[Vector2i] = [Vector2i(2, 2), Vector2i(4, 2), Vector2i(6, 2), Vector2i(8, 2), Vector2i(10, 2), Vector2i(12, 2)]


static func crew(make: Callable, run_seed: int, names: Array[String], mode: ServerConfig.Mode = ServerConfig.Mode.FRIENDS) -> Array:
	var s: Scenario = make.call({"seed": run_seed, "fixture": B.room(), "mode": mode})
	var out: Array[MinerHandle] = []
	for i: int in names.size():
		var h: MinerHandle = s.add_miner(names[i], TILES[i])
		h.brain = null
		out.append(h)
	s.step(2)
	return [s, out]


## Makes the given entities Hands (stand-ins) for the census and the heard rule.
static func hands(s: Scenario, entities: Dictionary) -> void:
	s.run.crew.is_hand_driven = func(e: int) -> bool: return entities.has(e)


static func fall(s: Scenario, h: MinerHandle, cause: FallCause.Cause = FallCause.Cause.ROOF_FALL) -> int:
	assert(s.run.falls.fall_unconscious(s.run, h.entity_id, cause))
	s.step(1)
	return s.run.tick


static func life(s: Scenario, h: MinerHandle) -> int:
	return s.run.miner_state.life(h.entity_id)


static func hurt(s: Scenario, h: MinerHandle) -> bool:
	return s.run.miner_state.miner(h.entity_id).overlays.hurt(s.run.tick)
