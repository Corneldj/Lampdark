extends GutTest
## GEN-16: Standard seeds generated from the shipped v1 set as a server generates them (MineLayouts'
## deriver, RepairList's draw, RunPlan's inputs, the run start's check and the homes). Every spine
## cell derives a layout; every planned point of interest has a template; each of its contents lines
## lies in its own slot, and whatever the plan put there (the run's parts) is placed.

const SEEDS: Array[int] = [16001, 16002, 16003]


func before_all() -> void:
	assert_true(Tuning.load_server())


func _planned(run_seed: int) -> LbLayouts:
	var layouts: LbLayouts = MineLayouts.for_run(run_seed)
	assert_not_null(layouts, "the shipped set loads")
	var list: RepairList = RepairList.for_run(run_seed, RepairList.Kind.STANDARD, false)
	var inputs: Dictionary = RunPlan.inputs_of(list, false, PackedStringArray(), "", "", "test")
	inputs["tuning"] = RunPlan.tuning()
	var plan: Dictionary = layouts.plan(inputs)
	assert_true(Variants.flag(plan["ok"]), str(plan.get("error", "")))
	var start: Dictionary = layouts.validate_run_start()
	assert_true(Variants.flag(start["ok"]), "the run start's check: every spine reaches, the gates hold")
	layouts.make_homes()
	return layouts


## The kind a contents line's thing is placed as (GEN-10's contents pass).
static func _kind_of(thing: String) -> String:
	match thing:
		"remains":
			return "remains"
		"phone":
			return "phone"
		"coats":
			return "coat_heap"
		"lore", "brass_checks":
			return "prop"
	return "item"


func test_standard_seeds_generate_their_spines_and_fill_every_planned_site() -> void:
	for run_seed: int in SEEDS:
		var layouts: LbLayouts = _planned(run_seed)
		var plan: Dictionary = layouts.plan_dict()
		for raw: Variant in Variants.array(plan["spines"]):
			for cell: Vector2i in Variants.array(Variants.dict(raw)["cells"]):
				var layout: Dictionary = layouts.derive_final(cell)
				assert_true(Variants.flag(layout.get("ok", false)), "seed %d: spine cell %s derives" % [run_seed, cell])
		var sites: Array = Variants.array(plan["sites"])
		assert_gt(sites.size(), 5, "seed %d: its planned sites" % run_seed)
		var checked: int = 0
		for i: int in sites.size():
			var site: Dictionary = Variants.dict(sites[i])
			var kind: String = str(site["kind"])
			var door: Vector2i = site["door"]
			var poi: Dictionary = layouts.poi_at(door)
			assert_false(str(poi.get("template", "")).is_empty(), "seed %d: the planned %s has a template" % [run_seed, kind])
			if str(poi.get("template", "")).is_empty():
				continue
			var slots: Array = Variants.array(poi["slots"])
			var placed: Array[Dictionary] = []
			for cell: Vector2i in Variants.array(poi["cells"]):
				for p: Variant in layouts.place(cell):
					var d: Dictionary = p
					if str(d["source"]) == "poi":
						placed.append(d)
			var region: Vector2i = poi["region"]
			var contents: Array = layouts.poi_contents(region, Variants.whole(poi["index"]))
			for raw: Variant in contents:
				var line: Dictionary = raw
				var at: int = Variants.whole(line["line"])
				if at < 0:
					continue
				assert_lt(at, slots.size(), "seed %d %s: line %d has a slot" % [run_seed, kind, at])
				if at >= slots.size():
					continue
				var slot: Rect2i = slots[at]
				checked += 1
				var want: String = _kind_of(str(line["thing"]))
				var found: bool = false
				for d: Dictionary in placed:
					var tile: Vector2i = d["tile"]
					found = found or (slot.has_point(tile) and str(d["kind"]) == want)
				assert_true(found, "seed %d %s: %s lies in slot %d" % [run_seed, kind, line["thing"], at])
			var holds: Dictionary = Variants.dict(site.get("holds", {}))
			for item: Variant in holds.keys():
				var n: int = 0
				for d: Dictionary in placed:
					n += 1 if str(d["thing"]) == str(item) else 0
				assert_gte(n, Variants.whole(holds[item]), "seed %d %s: the plan's %s placed" % [run_seed, kind, item])
		assert_gt(checked, sites.size(), "seed %d: its contents lines checked" % run_seed)
