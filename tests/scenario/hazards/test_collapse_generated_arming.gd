extends "res://tests/scenario/kit/scenario_test.gd"
## HAZ-03 with GEN-10 and GEN-11: in a generated mine, each armed collapse placement of a loaded cell
## stands armed (its tell, SND-02's hook on its rubble) once the cell has committed; unarmed
## alternates stand inert. A cell leaving lets its points go, and they are armed again when it
## comes back.

const Specs = preload("res://tests/unit/gen/template_specs.gd")


## GEN-11's grid road pack with a collapse alternate in every biome's grid (across its north column,
## at the biome's road width).
static func pack() -> PackedByteArray:
	var specs: Array = []
	for shape: String in ["straight", "bend_5", "bend_10", "bend_15", "crossing"]:
		specs.append(Specs.main_road_spec("main_" + shape, shape, false))
	specs.append(Specs.main_road_spec("main_straight_oldfall", "straight", true))
	for biome: String in ["pit_bottom", "seam", "old_workings", "black_seam", "old_mens"]:
		var grid: Dictionary = Specs.grid_spec("%s_grid" % biome, "biome_cell", biome, 1.0)
		var w: int = int(Variants.number(Specs.BIOME_WIDTH.get(biome, 3)))
		var across: Array = []
		for x: int in range(5 - w / 2, 5 - w / 2 + w):
			across.append([x, 2, "#"])
		grid["collapses"] = [{"id": 1, "tiles": across}]
		specs.append(grid)
		specs.append(Specs.grid_spec("%s_plain" % biome, "fallback", biome, 1.0))
	var problems: Array[String] = []
	var out: PackedByteArray = Specs.pack(specs, problems)
	assert(problems.is_empty(), str(problems))
	return out


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_placements_arm_as_cells_load() -> void:
	var s: Scenario = make({"seed": 4111, "generated": {"pack": pack(), "centres": [Vector2i(3, 0)]}})
	assert_true(s.run_until(func(sc: Scenario) -> bool: return sc.mine.native.loaded_cells().size() >= 60, 600), "the window generated")
	# A miner out there keeps it loaded (GEN-11 evicts what no miner or creature holds).
	var found: Variant = CreatureStarts.nearest_floor(s.run, Vector2i(70, 10), 12)
	assert_true(found is Vector2i, "floor out there")
	var floor_tile: Vector2i = found
	var ann: MinerHandle = s.add_miner("ann", floor_tile)
	ann.brain = null
	s.step(4)
	var placed: Array[int] = []
	var alternates: int = 0
	for cell: Vector2i in s.mine.native.loaded_cells():
		alternates += s.mine.native.collapses(cell).size()
		for p: Dictionary in s.run.placed.of_kind(cell, "collapse"):
			placed.append(CollapsePoints.point_id(cell, int(Variants.number(p["collapse"]))))
	placed.sort()
	gut.p("%d alternates in %d cells, %d armed" % [alternates, s.mine.native.loaded_cells().size(), placed.size()])
	assert_gt(placed.size(), 0, "some are armed")
	assert_lt(placed.size(), alternates, "and some stand inert")
	var points: Array = s.run.collapses.points.keys()
	points.sort()
	assert_eq(points, placed, "exactly the armed placements stand armed")
	for raw: Variant in points:
		var p: CollapsePoints.Point = s.run.collapses.points[raw]
		assert_true(s.run.registry.has(p.tell), "a tell for %d" % p.id)
		assert_true(s.run.noise.collapse.armed().has(p.id))
		for t: Vector2i in p.rubble:
			assert_false(s.mine.native.is_solid(t), "standing: its road open at %s" % t)
	# A cell near Ann leaves, and comes back (GEN-11 loads within 4 cells of her).
	var hers: Vector2i = WorldCoords.cell_of(floor_tile)
	var first: CollapsePoints.Point = null
	for raw: Variant in points:
		var q: CollapsePoints.Point = s.run.collapses.points[raw]
		if maxi(absi(q.cell.x - hers.x), absi(q.cell.y - hers.y)) <= 3 and q.cell != hers:
			first = q
			break
	assert_not_null(first, "a point near her")
	var cell: Vector2i = first.cell
	var tell: int = first.tell
	# Ann goes far off: the cell is evicted, and its point let go.
	s.run.movement.place(s.run, ann.entity_id, Vector2(cell * 20) + Vector2(10.5 + 20 * 9, 10.5))
	assert_true(s.run_until(func(sc: Scenario) -> bool: return not sc.mine.native.is_loaded(cell), 600), "the cell leaves")
	assert_false(s.run.collapses.points.has(first.id), "its point let go")
	assert_false(s.run.registry.has(tell), "its tell gone")
	assert_false(s.run.noise.collapse.armed().has(first.id))
	# She comes back: GEN-11 derives it again, and it stands armed again.
	s.run.movement.place(s.run, ann.entity_id, Vector2(floor_tile) + Vector2(0.5, 0.5))
	assert_true(s.run_until(func(sc: Scenario) -> bool: return sc.run.collapses.points.has(first.id), 600), "armed again when it is back")
	assert_true(s.mine.native.is_loaded(cell))
