extends RefCounted
## Helpers for MNR-02's tests: a long road, and per-tick records of the miner's gait.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")


static func road(width: int = 80) -> FixtureMap:
	return FixtureMap.from_ascii(PackedStringArray(["#".repeat(width), "#a" + ".".repeat(width - 3) + "#", "#".repeat(width)]))


## gait per tick (MinerMotion.RUN / WALK / STILL ...) for one slot, appended each tick.
static func track(s: Scenario, slot: int) -> Array[int]:
	var gaits: Array[int] = []
	s.on_tick = func(sc: Scenario) -> void: gaits.append(sc.run.movement.miner(slot).state.gait)
	return gaits


static func count_run(gaits: Array[int]) -> int:
	return gaits.filter(func(g: int) -> bool: return g == MinerMotion.RUN).size()


static func pants(s: Scenario) -> Array:
	return s.run.noise.event_log.filter(func(e: NoiseSystem.Event) -> bool: return e.type == NoiseTypes.Type.PANTING)
