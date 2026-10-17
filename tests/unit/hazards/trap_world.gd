extends RefCounted
## HAZ-01's tests: a road three tiles wide, a man-trap laid on it at TRAP, and helpers.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")
const C = preload("res://tests/unit/hazards/collapse_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")
const RW = preload("res://tests/unit/mnr/ring_world.gd")

const ROAD: PackedStringArray = [
	"########################################",
	"#......................................#",
	"#......................................#",
	"#......................................#",
	"########################################",
]
## The trap's tile, in the road's middle row.
const TRAP: Vector2i = Vector2i(10, 2)


static func cfg(run_seed: int, extra: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {"seed": run_seed, "fixture": FixtureMap.from_ascii(ROAD), "slots": 8}
	out.merge(extra, true)
	return out


## Every floor tile of the road at `value` (0.6: base camp's level, identity for small things).
static func light(s: Scenario, value: float = 0.6) -> int:
	var tiles: Array = []
	for y: int in range(1, 4):
		for x: int in range(1, 39):
			tiles.append(Vector2i(x, y))
	return s.run.light.grid.add_area("emergency", LbLightGrid.COLOUR_WHITE, 0, value, tiles)


## A miner stood still with its centre exactly at `at`.
static func miner_at(s: Scenario, name: String, at: Vector2) -> MinerHandle:
	return C.miner_at(s, name, at)


static func events_of(s: Scenario, type: NoiseTypes.Type) -> Array[NoiseSystem.Event]:
	return C.events_of(s, type)


## The trap at TRAP; `victim` stepped onto it. Returns the trap's entity.
static func catch(s: Scenario, victim: MinerHandle) -> int:
	var trap: int = s.run.man_traps.place(s.run, TRAP)
	s.run.movement.place(s.run, victim.entity_id, Vector2(TRAP) + Vector2(0.5, 0.5))
	s.step(1)
	assert(s.run.holds.caught_in(victim.entity_id) != null, "caught")
	return trap


## The tick an action of `verb` started for `miner`, stepping until it does (-1 if never).
static func started(s: Scenario, miner: int, verb: StringName, ticks: int) -> int:
	for _i: int in ticks:
		var a: TimedAction = s.run.inventory.actions.get(miner, null)
		if a != null and a.verb == verb:
			return a.started_tick
		s.step()
	return -1
