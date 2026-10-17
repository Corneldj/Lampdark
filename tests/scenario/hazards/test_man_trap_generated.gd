extends "res://tests/scenario/kit/scenario_test.gd"
## HAZ-01 with GEN-10, GEN-11 and GEN-13: in a run generated from the shipped set, every man-trap
## GEN-10 places (the homes' 4-8 on the lair's approaches among them) is a set TRAP entity on its tile
## once its cell is loaded. Sprung, it is GEN-13's record: its cell evicted and committed again, or
## its run resumed from a save, it comes back sprung, with no snap.

const Specs = preload("res://tests/unit/gen/template_specs.gd")
const S = preload("res://tests/scenario/net/save_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _cfg(run_seed: int, saves: bool = false) -> Dictionary:
	return {"seed": run_seed, "generated": {"pack": Specs.shipped_pack(), "plan": true}, "saves": saves}


## The approach traps' tiles, their cells loaded and their traps spawned, a miner standing by the first
## so GEN-11 keeps them (a cell nobody is near goes).
func _approaches(s: Scenario) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var cells: Array[Vector2i] = []
	for raw: Variant in Variants.array(s.generation.layouts.homes_dict()["lair_traps"]):
		var t: Vector2i = Variants.dict(raw)["tile"]
		tiles.append(t)
		if not cells.has(WorldCoords.cell_of(t)):
			cells.append(WorldCoords.cell_of(t))
	s.generation.start(cells)
	var by: Vector2i = tiles[0]
	for step: Vector2i in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if s.mine.native.is_walkable(tiles[0] + step) and not tiles.has(tiles[0] + step):
			by = tiles[0] + step
			break
	assert_ne(by, tiles[0], "floor beside the first trap")
	s.add_miner("warden", by)
	s.step(2)
	return tiles


func _trap_at(s: Scenario, tile: Vector2i) -> int:
	for raw: Variant in s.run.man_traps.traps.keys():
		var t: ManTraps.Trap = s.run.man_traps.traps[raw]
		if t.tile == tile:
			return t.entity
	return 0


func test_every_placed_man_trap_is_set_on_its_tile() -> void:
	var s: Scenario = make(_cfg(4701))
	var tiles: Array[Vector2i] = _approaches(s)
	assert_between(tiles.size(), Tuning.i(&"traps.man_trap_approach_min"), Tuning.i(&"traps.man_trap_approach_max"), "4-8 on the approaches")
	for t: Vector2i in tiles:
		var trap: int = _trap_at(s, t)
		assert_ne(trap, 0, "a trap at %s" % t)
		assert_true(s.run.man_traps.is_set(trap), "set")
		assert_eq(s.run.registry.get_entity(trap).kind, WorldIds.EntityKind.TRAP)
	# Every loaded cell's man-trap placements have their entity, and nothing else is a trap.
	var placed: int = 0
	for cell: Vector2i in s.mine.native.loaded_cells():
		for p: Dictionary in s.run.placed.of_kind(cell, "man_trap"):
			placed += 1
			var at: Vector2i = p["tile"]
			assert_ne(_trap_at(s, at), 0, "GEN-10's man-trap at %s spawned" % at)
	assert_eq(s.run.man_traps.traps.size(), placed, "one entity for each placement")


func test_sprung_it_stays_sprung_through_eviction() -> void:
	var s: Scenario = make(_cfg(4702))
	var tile: Vector2i = _approaches(s)[0]
	var cell: Vector2i = WorldCoords.cell_of(tile)
	s.run.stones.landed.emit(tile)
	s.step(2)
	assert_false(s.run.man_traps.is_set(_trap_at(s, tile)), "sprung by a stone")
	s.run.noise.event_log.clear()
	assert_true(s.mine.native.unload(cell), "its cell leaves")
	s.step(2)
	assert_eq(_trap_at(s, tile), 0, "and its trap with it")
	s.generation.start([cell])
	assert_true(s.mine.native.is_loaded(cell), "the cell comes back, generated")
	s.step(3)
	var back: int = _trap_at(s, tile)
	assert_ne(back, 0, "its trap back on its tile")
	assert_false(s.run.man_traps.is_set(back), "sprung, as GEN-13 recorded it")
	for e: NoiseSystem.Event in s.run.noise.event_log:
		assert_ne(e.type, NoiseTypes.Type.MANTRAP_SNAP, "and no snap")


func test_sprung_it_stays_sprung_through_a_resume() -> void:
	S.clear(4703)
	var s: Scenario = make(_cfg(4703, true))
	var tile: Vector2i = _approaches(s)[0]
	s.run.stones.landed.emit(tile)
	s.step(2)
	assert_false(s.run.man_traps.is_set(_trap_at(s, tile)))
	assert_false(s.run.saves.snapshot(s.run).is_empty(), "saved")
	var path: String = S.snapshot_path(s)
	S.kill(s)
	var opened: Dictionary = SaveResume.open_file(path)
	assert_true(Variants.flag(opened["ok"]), str(opened["message"]))
	var b: Scenario = make(_cfg(4703, true))
	SaveResume.apply(b.run, b.net, opened)
	b.rejoin("warden")
	b.generation.start([WorldCoords.cell_of(tile)])
	b.step(3)
	var back: int = _trap_at(b, tile)
	assert_ne(back, 0, "resumed, its trap on its tile")
	assert_false(b.run.man_traps.is_set(back), "and sprung")
