extends "res://tests/scenario/kit/scenario_test.gd"
## GEN-11: a generated cell is evicted when everyone is more than 6 cells away and derived again
## on return, identical; its diff replays (GEN-13). The cell holds dropped and moved items, an air
## door worked open, chalk and a collapse fallen (HAZ-03's FALL record, replayed by CollapsePoints).

const Specs = preload("res://tests/unit/gen/template_specs.gd")
const W = preload("res://tests/scenario/world/diff_world.gd")

## A pit-bottom cell with an air door on an alcove and a collapse alternate.
const CELL: Vector2i = Vector2i(1, 1)


func before_all() -> void:
	assert_true(Tuning.load_server())


## The road pack, its only pit-bottom cell the grid with an alcove at (2, 2) behind an air door at
## (2, 3) and a collapse across the north column (y 2, x 4-6).
static func pack() -> PackedByteArray:
	var specs: Array = []
	for shape: String in ["straight", "bend_5", "bend_10", "bend_15", "crossing"]:
		specs.append(Specs.main_road_spec("main_" + shape, shape, false))
	specs.append(Specs.main_road_spec("main_straight_oldfall", "straight", true))
	for biome: String in ["pit_bottom", "seam", "old_workings", "black_seam", "old_mens"]:
		var grid: Dictionary = Specs.grid_spec("%s_grid" % biome, "biome_cell", biome, 1.0)
		if biome == "pit_bottom":
			var rows: Array = Variants.array(grid["rows"]).duplicate()
			rows[2] = str(rows[2]).substr(0, 2) + "." + str(rows[2]).substr(3)
			rows[3] = str(rows[3]).substr(0, 2) + "D" + str(rows[3]).substr(3)
			grid["rows"] = rows
			grid["collapses"] = [{"id": 1, "tiles": [[4, 2, "#"], [5, 2, "#"], [6, 2, "#"]]}]
		specs.append(grid)
		specs.append(Specs.grid_spec("%s_plain" % biome, "fallback", biome, 1.0))
	var problems: Array[String] = []
	var out: PackedByteArray = Specs.pack(specs, problems)
	assert(problems.is_empty(), str(problems))
	return out


func test_a_cell_left_and_returned_to_comes_back_as_it_was() -> void:
	var s: Scenario = make({"seed": 4111, "generated": {"pack": pack()}})
	assert_true(s.mine.native.is_loaded(CELL), "the cell is in base camp's window")
	var base: Vector2i = CELL * 20
	var door_tiles: Array[Vector2i] = [base + Vector2i(2, 3)]
	assert_not_null(s.run.air_doors.door_at(door_tiles[0]), "the template's air door")
	var fresh: int = s.mine.native.digest(CELL)
	# Things done in the cell: items dropped and one moved, the door worked open, chalk, a fall.
	var ann: MinerHandle = s.add_miner("ann", base + Vector2i(2, 4), {"facing_deg": 270.0})
	ann.brain = null
	ann.at(s.run.tick).face(270.0)
	s.step(2)
	W.work_door(s, ann)
	assert_true(s.run.air_doors.door_at(door_tiles[0]).open, "worked open")
	var spanner: int = W.put(s, ItemKinds.Kind.SPANNER, base + Vector2i(10, 10))
	W.put(s, ItemKinds.Kind.FUSE, base + Vector2i(5, 10))
	s.run.registry.move(spanner, Vector2(base + Vector2i(14, 10)) + Vector2(0.5, 0.5))
	s.run.inventory.world.moved(s.run, spanner)
	s.run.chalk.store.put(s.run, base + Vector2i(10, 15), ChalkMarks.Surface.FLOOR, ChalkMarks.glyph(ChalkMarks.Kind.DIGIT_3), 1)
	s.mine.native.set_collapse(CELL, 1, true)
	s.run.diff_log.record(CELL, DiffLog.Kind.FALL, "collapse:1", {"fallen_at": s.run.tick, "cuts": []})
	s.step(2)
	var before: int = s.mine.native.digest(CELL)
	assert_ne(before, fresh, "the door and the fall changed the cell")
	var items_before: Dictionary = W.floor_items(s)
	var chalk_before: int = s.run.chalk.store.glyph_at(base + Vector2i(10, 15), ChalkMarks.Surface.FLOOR)
	# Away 12 cells along the main road: the cell goes.
	s.run.movement.place(s.run, ann.entity_id, Vector2(Vector2i(13, 0) * 20) + Vector2(1.5, 10.5))
	s.step(4)
	assert_false(s.mine.native.is_loaded(CELL), "evicted")
	assert_eq(W.floor_items(s).size(), 0, "its items left with it")
	s.run.chalk.store.marks.clear()
	# Back: derived again, its diff replayed.
	s.run.movement.place(s.run, ann.entity_id, Vector2(base + Vector2i(2, 4)) + Vector2(0.5, 0.5))
	s.step(4)
	assert_true(s.mine.native.is_loaded(CELL), "derived again on return")
	assert_eq(s.mine.native.digest(CELL), before, "the same layout and the same replayed state")
	assert_true(s.run.air_doors.door_at(door_tiles[0]).open, "the door still open")
	assert_false(s.mine.native.is_walkable(base + Vector2i(5, 2)), "the fall still down")
	assert_eq(W.floor_items(s), items_before, "the items where they were left")
	assert_eq(s.run.chalk.store.glyph_at(base + Vector2i(10, 15), ChalkMarks.Surface.FLOOR), chalk_before, "the chalk back")
	assert_eq(s.generation.missing_sight_ticks, 0)
