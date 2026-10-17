extends GutTest
## GEN-09 through LbLayouts as MineLayouts sets it up from tuning: with the run's plan every planned
## site is a point of interest of its region, planned ones first in plan order, and holds what the
## plan put there with its kind's table round it; the canary home names the canary station; and no
## point-of-interest key reaches a client's tuning. (A planned site no template fits keeps its
## biome's cells and its spine's door, with no slots.)

const JOBS: Array[String] = ["power", "fuel", "magneto", "drive_belt", "brake_shoes", "rope_clamps", "start"]


func before_all() -> void:
	assert_true(Tuning.load_server())


func _planned(run_seed: int) -> LbLayouts:
	var layouts: LbLayouts = MineLayouts.for_run(run_seed)
	assert_not_null(layouts)
	var plan: Dictionary = layouts.plan({"list_kind": RepairList.Kind.FULL, "jobs": PackedStringArray(JOBS), "cans": 6,
		"solo": false, "draw": PackedStringArray(), "staging": "", "hard_variant": "", "data_version": "test", "tuning": RunPlan.tuning()})
	assert_true(Variants.flag(plan["ok"]), str(plan["error"]))
	return layouts


## {thing: count} of a point of interest's contents.
func _counts(contents: Array) -> Dictionary:
	var out: Dictionary = {}
	for raw: Variant in contents:
		var thing: String = str(Variants.dict(raw)["thing"])
		out[thing] = int(Variants.number(out.get(thing, 0))) + 1
	return out


func test_every_planned_site_is_a_point_of_interest_holding_its_plan() -> void:
	var layouts: LbLayouts = _planned(9101)
	var sites: Array = Variants.array(layouts.plan_dict()["sites"])
	assert_gt(sites.size(), 8)
	for i: int in sites.size():
		var site: Dictionary = Variants.dict(sites[i])
		var door: Vector2i = site["door"]
		var poi: Dictionary = layouts.poi_at(door)
		assert_false(poi.is_empty(), "site %d at its door" % i)
		assert_eq(str(poi["kind"]), str(site["kind"]))
		assert_eq(int(Variants.number(poi["planned"])), i)
		assert_eq(Variants.array(poi["cells"]).size(), Variants.array(site["cells"]).size())
		if str(poi["template"]).is_empty():
			assert_eq(Variants.array(poi["slots"]).size(), 0, "no template, no slots")
		var region: Vector2i = poi["region"]
		var layout: Dictionary = layouts.poi_region(region)
		var listed: Dictionary = Variants.dict(Variants.array(layout["pois"])[int(Variants.number(poi["index"]))])
		assert_eq(int(Variants.number(listed["planned"])), i, "the region lists it at its index")
		var counts: Dictionary = _counts(layouts.poi_contents(region, int(Variants.number(poi["index"]))))
		var holds: Dictionary = Variants.dict(site["holds"])
		for item: Variant in holds.keys():
			assert_eq(int(Variants.number(counts.get(str(item), 0))), int(Variants.number(holds[item])), "%s holds its planned %s" % [site["kind"], item])
		if str(site["kind"]) == "substation":
			assert_eq(int(Variants.number(counts.get("phone", 0))), 1, "the substation's phone")


func test_a_region_holds_one_or_two_and_none_in_ring_zero() -> void:
	var layouts: LbLayouts = _planned(9102)
	for y: int in range(-3, 3):
		for x: int in range(-3, 3):
			var layout: Dictionary = layouts.poi_region(Vector2i(x, y))
			var pois: Array = Variants.array(layout["pois"])
			assert_lte(pois.size(), 2)
			for raw: Variant in pois:
				for cell: Vector2i in Variants.array(Variants.dict(raw)["cells"]):
					var centre: Vector2 = Vector2(cell * WorldIds.CELL_TILES) + Vector2(10, 10)
					assert_gte(centre.distance_to(Vector2(10, 10)), 80.0 - 1e-6, "ring 0 holds none")


func test_the_canary_home_names_the_canary_station() -> void:
	var layouts: LbLayouts = _planned(9103)
	var bytes: PackedByteArray = LbLayouts.canary_home(Vector2i(2, -1))
	assert_eq(bytes.size(), 16)
	layouts.set_home("canary", bytes)
	assert_eq(layouts.home("canary"), bytes)


func test_no_point_of_interest_key_reaches_a_client() -> void:
	var table: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string("res://data/tuning/_client.json")))
	for key: String in Variants.dict(table.get("keys", table)).keys():
		assert_false(key.begins_with("mine.poi_"), "%s is server-only" % key)
		assert_false(key.begins_with("mine.lamp_cabin") or key.begins_with("mine.first_aid"), "%s is server-only" % key)
