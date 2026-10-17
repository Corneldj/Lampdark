extends "res://tests/scenario/kit/scenario_test.gd"
## GEN-16 for CRT-15 and CRT-18: in a run generated from the shipped set, the Stythe's lair is the
## lair template's. Every tile of the plan's lair site is the lair, its start tile among them, and
## none beyond its door; the row is the template's first slot (the men laid out) past the remains
## the plan laid there, room for the whole crew, every place on floor; the Stythe lays its first
## body in the first of them.

const Specs = preload("res://tests/unit/gen/template_specs.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


static func _lair_site(layouts: LbLayouts) -> Dictionary:
	for raw: Variant in Variants.array(layouts.plan_dict()["sites"]):
		var site: Dictionary = Variants.dict(raw)
		if str(site["kind"]) == "lair":
			return site
	return {}


func test_the_lair_is_its_templates() -> void:
	for run_seed: int in [16101, 16102, 16103]:
		var s: Scenario = make({"seed": run_seed, "generated": {"pack": Specs.shipped_pack(), "plan": true, "creatures": true}})
		var layouts: LbLayouts = s.generation.layouts
		var site: Dictionary = _lair_site(layouts)
		assert_false(site.is_empty(), "seed %d: a lair planned" % run_seed)
		var door: Vector2i = site["door"]
		var poi: Dictionary = layouts.poi_at(door)
		assert_false(str(poi["template"]).is_empty(), "seed %d: the lair has its template" % run_seed)
		var cells: Array[Vector2i] = []
		cells.assign(Variants.array(poi["cells"]))
		s.generation.start(cells)
		var lair: StytheLair = s.run.stythe_lair
		for cell: Vector2i in cells:
			assert_true(lair.is_lair(cell * WorldIds.CELL_TILES + Vector2i(10, 10)), "seed %d: cell %s is the lair" % [run_seed, cell])
		var side: Vector2i = {"north": Vector2i(0, -1), "south": Vector2i(0, 1), "east": Vector2i(1, 0), "west": Vector2i(-1, 0)}[str(poi["door_side"])]
		assert_false(lair.is_lair((door + side) * WorldIds.CELL_TILES + Vector2i(10, 10)), "seed %d: beyond its door is not" % run_seed)
		var stythe: StytheCreature = null
		for c: Creature in s.run.creatures.creatures:
			if c is StytheCreature:
				stythe = c as StytheCreature
		assert_not_null(stythe, "seed %d: the Stythe started" % run_seed)
		if stythe != null:
			assert_true(lair.is_lair(stythe.lair), "seed %d: its start tile is in its lair" % run_seed)
		var places: Rect2i = Variants.array(poi["slots"])[0]
		var men: Dictionary = {}
		for cell: Vector2i in cells:
			for raw: Variant in layouts.place(cell):
				var p: Dictionary = raw
				var tile: Vector2i = p["tile"]
				if str(p["source"]) == "poi" and str(p["kind"]) == "remains" and places.has_point(tile):
					men[tile] = true
		assert_between(men.size(), 2, 4, "seed %d: the men laid out on the row" % run_seed)
		var row: Array[Vector2i] = lair.row()
		assert_eq(row.size(), places.get_area() - men.size(), "seed %d: the row is every place past them" % run_seed)
		assert_gte(row.size(), 4, "seed %d: room for the whole crew" % run_seed)
		for t: Vector2i in row:
			assert_true(places.has_point(t) and not men.has(t), "seed %d: %s a free place on the row" % [run_seed, t])
			assert_true(s.run.mine.native.is_walkable(t), "seed %d: %s on floor" % [run_seed, t])
		assert_eq(lair.next_slot(), 0, "seed %d: the first body goes in the first free place" % run_seed)
		assert_true(lair.tiles().has(row[0]), "seed %d: the row among the lair's floor" % run_seed)
