extends RefCounted
## GEN-13's tests: a road three cells long (row 1, x 1-58) with an air door at (45, 1) in cell
## (2, 0); a cell evicted (GEN-01's unload) and committed again from its fixture file, as GEN-11
## re-derives it; and the live state a replay must reproduce, in canonical form.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")

const DOOR: Vector2i = Vector2i(45, 1)
const FAR: Vector2i = Vector2i(2, 0)


static func road() -> FixtureMap:
	var w: int = 60
	return FixtureMap.from_ascii(PackedStringArray(["#".repeat(w), "#" + ".".repeat(44) + "D" + ".".repeat(13) + "#", "#".repeat(w)]))


static func make(run_seed: int, overrides: Dictionary = {}) -> Scenario:
	return Scenario.create({"seed": run_seed, "fixture": road(), "overrides": overrides})


## A miner on the road, scripted (no brain), facing east.
static func miner(s: Scenario, name: String, tile: Vector2i) -> MinerHandle:
	var h: MinerHandle = s.add_miner(name, tile, {"facing_deg": 0.0})
	h.brain = null
	h.at(s.run.tick).face(0.0)
	return h


## Unloads `cell` at the next stage 5 (its owners pack what lies there first).
static func evict(s: Scenario, cell: Vector2i) -> void:
	s.run.mine.queue_unload(cell)
	s.step(1)


## Commits `cell` again from its fixture file, as generation re-derives it; its diff replays.
static func restore(s: Scenario, cell: Vector2i) -> void:
	for file: Dictionary in s.fixture.cells:
		var data: LbCellData = CellFile.from_dict(file, "diff_world")
		if data != null and data.get_coord() == cell:
			s.run.mine.queue_commit(data)
	s.step(1)


## An item lying at `tile` (the centre), its entity.
static func put(s: Scenario, kind: ItemKinds.Kind, tile: Vector2i, state: Dictionary = {}, count: int = 1) -> int:
	var it: Item = s.run.inventory.world.make(kind, count, state)
	return s.run.inventory.world.put(s.run, it, Vector2(tile) + Vector2(0.5, 0.5))


## Every item lying in the world, by uid: [kind, count, state, x, y], states canonical.
static func floor_items(s: Scenario) -> Dictionary:
	var out: Dictionary = {}
	for raw: Variant in s.run.inventory.world.items.keys():
		var it: Item = s.run.inventory.world.items[raw]
		var e: SimEntity = s.run.registry.get_entity(int(Variants.number(raw)))
		out[it.uid] = [it.kind, it.count, DiffLog.canonical(it.state), e.position.x, e.position.y]
	return out


## The entity of the item with `uid` lying in the world, or 0.
static func entity_of(s: Scenario, uid: int) -> int:
	for raw: Variant in s.run.inventory.world.items.keys():
		var it: Item = s.run.inventory.world.items[raw]
		if it.uid == uid:
			return int(Variants.number(raw))
	return 0


## Works the door with `h` standing beside it (interact held long enough).
static func work_door(s: Scenario, h: MinerHandle) -> void:
	var need: int = roundi(Tuning.f(&"mine.air_door_operate_s") * Tuning.f(&"net.tick_hz"))
	h.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, need + 6)
	s.step(need + 10)


static func door(s: Scenario) -> AirDoorSystem.Door:
	return s.run.air_doors.door_at(DOOR)
