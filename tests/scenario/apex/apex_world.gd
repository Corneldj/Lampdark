extends RefCounted
## LFT-09's scenarios: base camp ready to start the engine (LFT-08's world), its first gate's road run
## on straight for `length` tiles through rock with a dead-end spur every 20 tiles, the creatures where
## a test puts them, and the engine's catch: the real start, or its signal alone.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const MinerHandle = preload("res://tests/scenario/kit/miner_handle.gd")
const E = preload("res://tests/unit/lift/engine_world.gd")
const B = preload("res://tests/scenario/world/basecamp_world.gd")
const W = preload("res://tests/unit/creatures/stythe_world.gd")
const C = preload("res://tests/scenario/basecamp/camp_world.gd")

## Every creature kind enabled (the Stythe's spawn reads it).
const ON: Dictionary = {"creatures.enabled": {"moth": 1, "tapper": 1, "stythe": 1}}
const N: int = 20


## Base camp, a full tank and every job but Start done, and the road run on; returns the road's gate.
static func world(s: Scenario, length: int = 220) -> Gate:
	E.ready(s)
	var gate: Gate = road_gate(s)
	extend(s, gate, length)
	return gate


static func road_gate(s: Scenario) -> Gate:
	return s.run.base_camp.gate_system.gate(str(s.run.base_camp.gates[0]["side"]))


## The tile `k` tiles out along the road's middle.
static func on_road(gate: Gate, k: int) -> Vector2i:
	return gate.middle() + gate.outward * k


## A rock tile `k` tiles out, `aside` tiles off the road's side.
static func in_rock(gate: Gate, k: int, aside: int = 4) -> Vector2i:
	return on_road(gate, k) + Vector2i(gate.outward.y, gate.outward.x) * aside


## The road (3 wide, as the gate) straight on for `length` tiles, through its own road cell (rebuilt
## with GEN-02's arches, its road carried to the far edge) and new cells of rock beyond, with a 1-wide
## spur 6 tiles long off one side every 20 tiles: dead ends for the Stythe to lurk in.
static func extend(s: Scenario, gate: Gate, length: int) -> void:
	var camp_side: int = s.run.base_camp.side
	var road_cells: Dictionary = {}
	for g: Dictionary in Basecamp.gate_specs(C.SEED, camp_side):
		var road: Array = B.road_cell(g)
		road_cells[road[0]] = road[1]
	var grids: Dictionary = {}
	var side: Vector2i = Vector2i(gate.outward.y, gate.outward.x)
	var floor_tiles: Array[Vector2i] = []
	for g: Vector2i in gate.tiles:
		for k: int in range(1, length + 1):
			floor_tiles.append(g + gate.outward * k)
	for k: int in range(20, length, 20):
		for j: int in range(2, 8):
			floor_tiles.append(on_road(gate, k) + side * j)
	for w: Vector2i in floor_tiles:
		var cell: Vector2i = Vector2i(floori(float(w.x) / N), floori(float(w.y) / N))
		if cell == Vector2i.ZERO:
			continue
		if not grids.has(cell):
			var rows: Array = []
			var from: PackedStringArray = road_cells.get(cell, PackedStringArray())
			for y: int in N:
				var row: Array = []
				for x: int in N:
					row.append(from[y][x] if not from.is_empty() else "#")
				rows.append(row)
			grids[cell] = rows
		var l: Vector2i = w - cell * N
		var grid: Array = grids[cell]
		grid[l.y][l.x] = "."
	for raw: Variant in grids.keys():
		var cell: Vector2i = raw
		var rows: PackedStringArray = PackedStringArray()
		for row: Array in Variants.array(grids[cell]):
			rows.append("".join(PackedStringArray(row)))
		if road_cells.has(cell):
			rows = Basecamp.apply_gate_arches(C.SEED, cell, rows, camp_side)
		if s.run.mine.native.is_loaded(cell):
			s.run.mine.native.unload(cell)
		s.run.mine.native.commit(CellFile.from_dict(B.cell_file(cell, rows), "road"))
		s.run.light.grid.on_cell_loaded(cell)


## A Moth asleep on a tile.
static func moth(s: Scenario, at: Vector2i) -> Moth:
	s.place_creature(WorldIds.EntityKind.MOTH, at)
	return s.run.creatures.creature_of_kind(WorldIds.EntityKind.MOTH)


static func tapper(s: Scenario, at: Vector2i) -> Tapper:
	s.place_creature(WorldIds.EntityKind.TAPPER, at)
	return s.run.creatures.creature_of_kind(WorldIds.EntityKind.TAPPER)


## A Stythe lurking at its lair.
static func stythe(s: Scenario, at: Vector2i, lair: Vector2i) -> StytheCreature:
	return W.stythe(s, at, lair)


## The engine catches now (its signal: the apex reads nothing else).
static func catch_now(s: Scenario) -> void:
	s.run.engine.engine_caught.emit(s.run.tick)


## The real start: Ann primes and cranks, Bob throttles on the clank. Returns the catch's tick.
static func start_engine(s: Scenario) -> int:
	var ann: MinerHandle = E.at(s, "ann", "engine_prime")
	E.prime(s, ann)
	E.move_to(s, ann, "engine_crank")
	var bob: MinerHandle = E.at(s, "bob", "engine_throttle")
	E.hold(s, ann, 200)
	assert(E.throttle_after_cue(s, bob, 0.5), "the engine catches")
	return s.run.engine.caught_at


static func tile_material(s: Scenario, t: Vector2i) -> int:
	return int(Variants.number(s.run.mine.native.material_at(t)))


## Steps while `check(tick)` holds, at most `ticks`; returns the ticks stepped (or -1 if it failed).
static func hold(s: Scenario, ticks: int, check: Callable) -> int:
	for i: int in ticks:
		s.step(1)
		if not Variants.flag(check.call(i)):
			return -1
	return ticks
