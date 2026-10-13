extends RefCounted
## Helpers for CRT-09: a road along row 5 through rock (rows 0-4 and 6-10), every tile in ring 1
## (hearing multiplier 1.0: talk carries 8 tiles), a real Tapper and miners, and server-side
## sounds standing in for SND-09's voice events and the items' bangs.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")


static func ring(n: int) -> void:
	var bounds: Array = [1000000, 1000001, 1000002, 1000003]
	for i: int in n:
		bounds[i] = 1 + i
	Tuning.set_dev_override("depth.ring_start_tiles", bounds)


static func road(width: int = 40) -> FixtureMap:
	var rows: PackedStringArray = PackedStringArray()
	for y: int in 11:
		rows.append(("#" + ".".repeat(width - 2) + "#") if y == 5 else "#".repeat(width))
	return FixtureMap.from_ascii(rows)


static func tapper(s: Scenario, at: Vector2i) -> Tapper:
	s.place_creature(WorldIds.EntityKind.TAPPER, at)
	var t: Tapper = s.run.creatures.creature_of_kind(WorldIds.EntityKind.TAPPER)
	return t


static func talk(s: Scenario, who: MinerHandle, np: float = -1.0) -> void:
	var at: Vector2 = s.run.registry.get_entity(who.entity_id).position
	s.run.noise.emit(NoiseTypes.Type.VOICE, Vector2i(floori(at.x), floori(at.y)), {"level_np": Tuning.f(&"voice.talk_np") if np < 0.0 else np,
		"mode": RoadGraphService.MODE_VOICE, "voice_id": 0, "source": who.entity_id})


static func bang(s: Scenario, tile: Vector2i, np: float, source: int) -> void:
	s.run.noise.emit(NoiseTypes.Type.RAIL_BANG, tile, {"level_np": np, "source": source})


static func life(s: Scenario, e: int) -> int:
	return s.run.miner_state.life(e)


## Steps until the Tapper is in `state_name` (or `limit` ticks); returns ticks stepped, -1 if not.
static func until_state(s: Scenario, t: Tapper, state_name: StringName, limit: int = 400) -> int:
	for i: int in limit:
		if t.state.name == state_name:
			return i
		s.step(1)
	return -1 if t.state.name != state_name else limit


## A Tapper at the wall above Ann (rock tile (10, 4), a usable face), Ann pinned by her own talk.
static func pinned(s: Scenario) -> Array:
	var ann: MinerHandle = s.add_miner("ann", Vector2i(10, 5))
	var t: Tapper = tapper(s, Vector2i(10, 4))
	t.follower.stop()
	s.step(2)
	talk(s, ann)
	until_state(s, t, &"pin", 60)
	return [ann, t]
