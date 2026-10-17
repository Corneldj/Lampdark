extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-05's stand-in substation (until GEN-16 gives the substation its template): in a generated
## run, once the plan's substation site's door cell is loaded the fuse board, the trip lever and the
## main switch stand on its floor (the board nearest the site's middle, the others at least two tiles
## from it and from each other). They go with the cell and come back with it, in the same places.

const Specs = preload("res://tests/unit/gen/template_specs.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


static func _site(layouts: LbLayouts) -> Dictionary:
	for raw: Variant in Variants.array(layouts.plan_dict()["sites"]):
		var site: Dictionary = Variants.dict(raw)
		if str(site["kind"]) == "substation":
			return site
	return {}


static func _floor_in(s: Scenario, cell: Vector2i) -> Vector2i:
	for y: int in WorldIds.CELL_TILES:
		for x: int in WorldIds.CELL_TILES:
			var t: Vector2i = cell * WorldIds.CELL_TILES + Vector2i(x, y)
			if s.run.mine.native.is_walkable(t):
				return t
	return Vector2i(-1, -1)


func test_the_stand_in_stands_in_the_substation_and_comes_back_with_it() -> void:
	var probe: Scenario = make({"seed": 5551, "generated": {"pack": Specs.road_pack(), "plan": true}})
	var site: Dictionary = _site(probe.generation.layouts)
	assert_false(site.is_empty(), "the plan has its substation")
	var door: Vector2i = site["door"]
	var s: Scenario = make({"seed": 5551, "generated": {"pack": Specs.road_pack(), "plan": true, "centres": [door]}})
	var power: PowerJob = s.run.power
	var at: Vector2i = _floor_in(s, door)
	assert_ne(at, Vector2i(-1, -1))
	var ann: MinerHandle = s.add_miner("ann", at)
	ann.brain = null
	s.step(3)
	assert_eq(power.anchors_from, "stand_in")
	var cells: Array[Vector2i] = []
	cells.assign(Variants.array(site["cells"]))
	var placed: Array[Vector2i] = []
	for name: String in PowerJob.FIXTURES:
		var p: Vector2 = power.anchors[name]
		var t: Vector2i = Vector2i(floori(p.x), floori(p.y))
		assert_true(cells.has(WorldCoords.cell_of(t)), "%s in the substation's cells" % name)
		assert_true(s.run.mine.native.is_walkable(t), "%s on its floor" % name)
		for other: Vector2i in placed:
			assert_gte(maxi(absi(t.x - other.x), absi(t.y - other.y)), 2, "two tiles apart at least")
		placed.append(t)
		var e: int = int(Variants.number(power.fixtures.get(name, 0)))
		assert_true(e != 0 and s.run.registry.has(e), "%s stands" % name)
	var first: Dictionary = power.anchors.duplicate()
	# Away to base camp: the cell goes, and its fixtures with it.
	s.run.movement.place(s.run, ann.entity_id, Vector2(10.5, 10.5))
	s.step(6)
	assert_false(s.run.mine.native.is_loaded(door), "the substation's cell let go")
	assert_eq(power.fixtures.size(), 0, "its fixtures with it")
	# Back: the same places.
	s.run.movement.place(s.run, ann.entity_id, Vector2(at) + Vector2(0.5, 0.5))
	s.step(6)
	assert_true(s.run.mine.native.is_loaded(door))
	assert_eq(power.anchors, first, "in the same places")
	assert_eq(power.fixtures.size(), 3, "standing again")
