extends "res://tests/scenario/kit/scenario_test.gd"
## GEN-10 (Gameplay §12.5): a generated run's placements spawn as its cells commit. Round base camp,
## each loaded cell's placements are LbLayouts.place's; each placed item lies on its tile with its
## state and its placement ID (GEN-13's key), the remains' items on their remains; phones stand on
## their fixtures; air doors are in the cell's tiles and GEN-15's doors; timber hooks join MNR-06's.
## A cell left and returned to holds its items once, GEN-13 replaying them, and an item taken from it
## never comes back. The plan's revolver lies loaded on its deputy on its spine cell. NET-08's audit
## passes all of it: no anchor, and nothing placed but what a client sees.

const Specs = preload("res://tests/unit/gen/template_specs.gd")
const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


## GEN-05's road pack with every biome's grid given what placement reads, each where GEN-04's
## validator wants it: a dead-end spur (2, 2)-(2, 4) with remains at its end, a wall fixture on its
## rock face, a door site at its mouth and a blackdamp run along it (remains in blackdamp go:
## GEN-10's exclusion); items, trap sites and a low road on the corridors; a gas area on a crossing; a collapse choking
## the north stub's road at y 2.
static func finds_pack() -> PackedByteArray:
	var specs: Array = [Specs.main_road_spec("main_straight", "straight", false), Specs.main_road_spec("main_bend_5", "bend_5", false),
		Specs.main_road_spec("main_bend_10", "bend_10", false), Specs.main_road_spec("main_bend_15", "bend_15", false),
		Specs.main_road_spec("main_crossing", "crossing", false), Specs.main_road_spec("main_straight_oldfall", "straight", true)]
	for biome: String in ["pit_bottom", "seam", "old_workings", "black_seam", "old_mens"]:
		var grid: Dictionary = Specs.grid_spec("%s_grid" % biome, "biome_cell", biome, 1.0)
		var rows: Array = Variants.array(grid["rows"]).duplicate()
		for spur_x: int in [2]:
			for y: int in [2, 3, 4]:
				var row: String = rows[y]
				rows[y] = row.substr(0, spur_x) + "." + row.substr(spur_x + 1)
		grid["rows"] = rows
		var w: int = int(Variants.number(Specs.BIOME_WIDTH.get(biome, 3)))
		var anchors: Array = Variants.array(grid["anchors"]).duplicate()
		anchors.append_array([["remains", 2, 2, 1, 1, [], ""], ["wall_fixture", 3, 3, 1, 1, [], ""], ["door_site", 2, 3, 1, 1, [], ""],
			["gas_dead_end", 2, 2, 1, 3, ["dead_end"], ""], ["item", 5, 5, 1, 1, [], ""], ["item", 15, 5, 1, 1, [], ""],
			["trap_site", 5, 15, 1, 1, [], ""], ["trap_site", 15, 15, 1, 1, [], ""], ["low_road", 10, 1, 1, 2, [], ""],
			["gas_area", 9, 9, 3, 3, [], ""]])
		grid["anchors"] = anchors
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


## pid -> [entity, Item] of every placed item lying in the world.
func _placed_items(s: Scenario) -> Dictionary:
	var out: Dictionary = {}
	for raw: Variant in s.run.inventory.world.items.keys():
		var it: Item = s.run.inventory.world.items[raw]
		if not it.placement.is_empty():
			if out.has(it.placement):
				out[it.placement] = [-1, null]  # twice: never allowed
			else:
				out[it.placement] = [int(Variants.number(raw)), it]
	return out


func _entities_at(s: Scenario, kind: WorldIds.EntityKind, tile: Vector2i) -> int:
	var n: int = 0
	for raw: Variant in Array(s.run.registry.ids_in_cell(WorldCoords.cell_of(tile))):
		var e: SimEntity = s.run.registry.get_entity(int(Variants.number(raw)))
		if e != null and e.kind == kind and e.tile() == tile:
			n += 1
	return n


func _base_camp_floor(s: Scenario) -> Vector2i:
	for r: int in 10:
		for dy: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				var t: Vector2i = Vector2i(10 + dx, 10 + dy)
				if s.mine.native.is_walkable(t):
					return t
	return Vector2i(10, 10)


func test_placements_spawn_with_their_cells_and_come_back_once() -> void:
	var s: Scenario = make({"seed": 4211, "generated": {"pack": finds_pack(), "plan": true}})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var placed: PlacementSpawner = s.run.placed
	assert_not_null(placed, "placement installed")
	var items: Dictionary = _placed_items(s)
	var seen: Dictionary = {}
	for cell: Vector2i in s.mine.native.loaded_cells():
		if cell == Vector2i.ZERO:
			continue
		var list: Array = Variants.array(placed.by_cell.get(cell, []))
		assert_eq(list, placed.layouts.place(cell), "cell %s holds its placements" % cell)
		for i: int in list.size():
			var p: Dictionary = list[i]
			var kind: String = p["kind"]
			var tile: Vector2i = p["tile"]
			seen[kind] = int(Variants.number(seen.get(kind, 0))) + 1
			match kind:
				"item":
					var pid: String = p["id"]
					assert_true(items.has(pid), "item %s spawned" % pid)
					if not items.has(pid):
						continue
					var entity: int = int(Variants.number(Variants.array(items[pid])[0]))
					assert_gt(entity, 0, "once only")
					if entity <= 0:
						continue
					var it: Item = Variants.array(items[pid])[1]
					assert_eq(s.run.registry.get_entity(entity).tile(), tile, "on its tile")
					assert_eq(str(ItemKinds.Kind.find_key(it.kind)), str(p["thing"]).to_upper())
					if it.kind == ItemKinds.Kind.GAUZE_LAMP:
						var oil: float = Variants.number(it.state.get("oil", -1.0))
						assert_true(oil >= 0.25 and oil <= 0.75, "a found lamp's oil")
						assert_false(Variants.flag(it.state.get("lit", true)), "unlit")
					if int(Variants.number(p["with"])) >= 0:
						var carrier: Dictionary = list[int(Variants.number(p["with"]))]
						assert_eq(str(carrier["kind"]), "remains")
						var on: Vector2i = carrier["tile"]
						assert_eq(on, tile, "on its remains")
				"phone":
					assert_eq(_entities_at(s, WorldIds.EntityKind.PHONE, tile), 1, "a phone on its fixture")
				"air_door":
					assert_not_null(s.run.air_doors.door_at(tile), "GEN-15's door")
					assert_eq(int(Variants.number(s.mine.native.material_at(tile))), WorldIds.TileMaterial.WOODEN_DOOR, "in the tiles")
	gut.p("placed round base camp: %s" % seen)
	for kind: String in ["landmark", "remains", "item", "phone", "air_door", "collapse"]:
		assert_gt(int(Variants.number(seen.get(kind, 0))), 0, "some %s" % kind)
	assert_true(s.run.lamps.hooks.size() > 50, "the cells' timber hooks are MNR-06's")
	# A holder in base camp; then every placed item in cells that can go (not pinned), one taken.
	var ann: MinerHandle = s.add_miner("ann", _base_camp_floor(s))
	ann.brain = null
	s.step(2)
	var pids: Array[String] = []
	var cells: Array[Vector2i] = []
	for c: Vector2i in s.mine.native.loaded_cells():
		if s.generation.pinned.has(c):
			continue
		for p: Variant in Variants.array(placed.by_cell.get(c, [])):
			if str(Variants.dict(p)["kind"]) == "item":
				pids.append(str(Variants.dict(p)["id"]))
				if not cells.has(c):
					cells.append(c)
	assert_gt(pids.size(), 1, "placed items in cells that can be left")
	if pids.size() < 2:
		return
	var taken: String = pids[0]
	var entity: int = int(Variants.number(Variants.array(_placed_items(s)[taken])[0]))
	assert_not_null(s.run.inventory.world.lift(s.run, entity, &"take", ann.entity_id), "taken")
	# Away 12 cells: the cell goes, and its items with it.
	s.run.movement.place(s.run, ann.entity_id, Vector2(Vector2i(13, 0) * 20) + Vector2(1.5, 10.5))
	s.step(4)
	for c: Vector2i in cells:
		assert_false(s.mine.native.is_loaded(c), "%s evicted" % c)
	for pid: String in pids:
		assert_false(_placed_items(s).has(pid), "%s left with its cell" % pid)
	# Back: each placed item once, the taken one never.
	s.run.movement.place(s.run, ann.entity_id, Vector2(_base_camp_floor(s)) + Vector2(0.5, 0.5))
	s.step(4)
	for c: Vector2i in cells:
		assert_true(s.mine.native.is_loaded(c), "%s derived again" % c)
	var back: Dictionary = _placed_items(s)
	assert_false(back.has(taken), "a taken item never comes back")
	for pid: String in pids.slice(1):
		assert_true(back.has(pid) and int(Variants.number(Variants.array(back[pid])[0])) > 0, "%s back, once" % pid)
	for v: Dictionary in audit.violations.slice(0, 6):
		gut.p("VIOLATION %s" % v)
	assert_eq(audit.violation_count, 0, "NET-08: no anchor, nothing unseen")


func test_the_revolver_lies_loaded_on_its_deputy() -> void:
	var s: Scenario = make({"seed": 4219, "generated": {"pack": finds_pack(), "plan": true}})
	var plan: Dictionary = s.run.placed.layouts.plan_dict()
	if not Variants.flag(plan["revolver"]):
		pass_test("no revolver this run")
		return
	var cell: Vector2i = plan["revolver_cell"]
	assert_true(s.run.placed.layouts.is_spine_cell(cell), "on a spine cell")
	# A stand-in holder there loads its window.
	s.run.registry.create(WorldIds.EntityKind.MOTH, Vector2(cell * 20) + Vector2(10.5, 10.5), SimEntity.FLAG_MOTIONLESS)
	s.step(3)
	assert_true(s.mine.native.is_loaded(cell))
	var list: Array = Variants.array(s.run.placed.by_cell.get(cell, []))
	var gun: Dictionary = {}
	for p: Variant in list:
		if str(Variants.dict(p)["thing"]) == "revolver":
			gun = p
	assert_false(gun.is_empty(), "the revolver is placed")
	if gun.is_empty():
		return
	var deputy: Dictionary = Variants.dict(list[int(Variants.number(gun["with"]))])
	assert_eq(str(deputy["kind"]), "remains")
	assert_eq(str(deputy["thing"]), "deputy")
	var lying: Dictionary = _placed_items(s)
	assert_true(lying.has(str(gun["id"])))
	var it: Item = Variants.array(lying[str(gun["id"])])[1]
	assert_eq(Revolver.rounds_in(it), Tuning.i(&"revolver.cylinder_rounds"), "six in the cylinder")


func test_the_homes_name_the_creatures_start_cells() -> void:
	var s: Scenario = make({"seed": 4223, "generated": {"pack": finds_pack(), "plan": true}})
	var layouts: LbLayouts = s.run.placed.layouts
	var homes: Dictionary = layouts.homes_dict()
	var cells: Array[Vector2i] = PlacementSpawner.start_cells(layouts)
	var roosts: Array = Variants.array(homes["roosts"])
	var start: int = int(Variants.number(homes["start_roost"]))
	if homes["hoard"] != null:
		var hoard: Vector2i = homes["hoard"]
		var expect: Vector2i = WorldCoords.cell_of(hoard)
		if start >= 0:
			var r: Rect2i = roosts[start]
			expect = WorldCoords.cell_of(r.position + r.size / 2)
		assert_true(cells.has(expect), "the Moth's start: its start roost, or the hoard")
	for raw: Variant in Variants.array(layouts.plan_dict()["sites"]):
		var site: Dictionary = Variants.dict(raw)
		if str(site["kind"]) == "lair":
			var door: Vector2i = site["door"]
			assert_true(cells.has(door), "the Stythe's lair")
	# The homes are in the header beside the plan, so a save keeps them.
	assert_eq(s.run.header.plan, layouts.plan_bytes())
	assert_false(layouts.home("start_roost").is_empty())
