extends RefCounted
## HAZ-03's tests: a mine pictured in ASCII with a collapse across its road. 'R' marks the rubble:
## floor while it stands, rock once it falls. Its Road Graph is cut as GEN-04's pipeline cuts a
## template's collapse (the fallen picture's zones and whole block), so a fall reroutes sound.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")
const B = preload("res://tests/unit/mnr/belt_world.gd")

## A road three tiles wide, 'R' across it at x 15-17: miners at a (west) and b (east).
const ROAD: PackedStringArray = [
	"########################################",
	"#..............RRR.....................#",
	"#a.............RRR....................b#",
	"#..............RRR.....................#",
	"########################################",
]
## The rubble's west edge and its tiles' x.
const WEST: int = 15
const EAST: int = 18


## The fixture: each cell holding 'R' gets collapse 1, standing floor and fallen rock.
static func fixture(rows: PackedStringArray = ROAD) -> FixtureMap:
	var standing: FixtureMap = FixtureMap.from_ascii(rows, {"R": "."})
	var fallen: FixtureMap = FixtureMap.from_ascii(rows, {"R": "#"})
	var size: int = WorldIds.CELL_TILES
	for i: int in standing.cells.size():
		var cell: Dictionary = standing.cells[i]
		var down: Dictionary = fallen.cells[i]
		var at: Array = Variants.array(cell["cell"])
		var origin: Vector2i = Vector2i(int(Variants.number(at[0])), int(Variants.number(at[1]))) * size
		var up_writes: Array = []
		var down_writes: Array = []
		for y: int in size:
			var row: String = rows[origin.y + y] if origin.y + y < rows.size() else ""
			for x: int in size:
				if origin.x + x < row.length() and row[origin.x + x] == "R":
					up_writes.append([y * size + x, "."])
					down_writes.append([y * size + x, "#"])
		if up_writes.is_empty():
			continue
		var zone_writes: Array = []
		var up_zones: Array = Variants.array(cell["zones"])
		var down_zones: Array = Variants.array(down["zones"])
		for y: int in size:
			for x: int in size:
				var a: int = int(Variants.number(Variants.array(up_zones[y])[x]))
				var b: int = int(Variants.number(Variants.array(down_zones[y])[x]))
				if a != b:
					zone_writes.append([y * size + x, a, b])
		cell["collapses"] = [{"id": 1, "standing": up_writes, "fallen": down_writes, "zones": zone_writes,
			"fallen_road_graph": Variants.dict(down.get("road_graph", {}))}]
	return standing


static func cfg(run_seed: int, rows: PackedStringArray = ROAD) -> Dictionary:
	return {"seed": run_seed, "fixture": fixture(rows), "slots": 8}


## Arms collapse 1 of `cell`; returns its point.
static func arm(s: Scenario, cell: Vector2i = Vector2i.ZERO) -> CollapsePoints.Point:
	var pid: int = s.run.collapses.arm_alternate(s.run, cell, 1)
	assert(pid != 0, "the alternate stands armed")
	return s.run.collapses.points[pid]


## A miner stood still at a point (its centre exactly there).
static func miner_at(s: Scenario, name: String, at: Vector2) -> MinerHandle:
	var h: MinerHandle = s.add_miner(name, Vector2i(floori(at.x), floori(at.y)))
	h.brain = null
	s.run.movement.place(s.run, h.entity_id, at)
	return h


## Starts the point's creak with a run step at `tile` (18 np); returns the trigger's tick.
static func trigger(s: Scenario, tile: Vector2i) -> int:
	s.run.noise.emit(NoiseTypes.Type.STEP_RUN, tile)
	var at: int = s.run.tick
	s.step()
	return at


## Steps until the point has fallen (its tell gone); the tick it fell, or -1.
static func until_fallen(s: Scenario, pid: int, ticks: int = 200) -> int:
	for _i: int in ticks:
		s.step()
		if not s.run.collapses.points.has(pid):
			return int(Variants.number(s.run.collapses.falls[s.run.collapses.falls.size() - 1]["tick"]))
	return -1


## Every noise event of a type logged so far.
static func events_of(s: Scenario, type: NoiseTypes.Type) -> Array[NoiseSystem.Event]:
	var out: Array[NoiseSystem.Event] = []
	for e: NoiseSystem.Event in s.run.noise.event_log:
		if e.type == type:
			out.append(e)
	return out
