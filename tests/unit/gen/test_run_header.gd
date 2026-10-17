extends GutTest
## GEN-08: the run header through LbLayouts and RunPlan. Made from the seed and the repair list, it
## records the generator, hash, template and data versions and the run conditions; its bytes round-
## trip exactly (a second deriver loading them has the same header and the same spines); a header
## for another seed, or bytes that are not one, are refused; and a snapshot keeps the bytes.

const Specs = preload("res://tests/unit/gen/template_specs.gd")
const STANDARD_JOBS: Array[String] = ["power", "fuel", "magneto", "rope_clamps", "start"]


func before_all() -> void:
	assert_true(Tuning.load_server())


func _layouts(run_seed: int) -> LbLayouts:
	var layouts: LbLayouts = MineLayouts.for_run(run_seed)
	assert_not_null(layouts)
	return layouts


## A deriver on GEN-07's road pack (grid cells and plain fallbacks for every biome): RunPlan.fix walks
## every spine (GEN-12), and the shipped pack cannot build one until GEN-16's templates.
func _road_layouts(run_seed: int) -> LbLayouts:
	var layouts: LbLayouts = LbLayouts.new()
	assert_true(layouts.load_pack(Specs.road_pack()))
	MineLayouts.configure(layouts, run_seed)
	return layouts


func _params(jobs: Array[String] = STANDARD_JOBS) -> Dictionary:
	return {"list_kind": RepairList.Kind.STANDARD, "jobs": PackedStringArray(jobs), "cans": 4, "solo": false,
		"draw": PackedStringArray(["dry_stores"]), "staging": "", "hard_variant": "", "data_version": "test-tuning",
		"tuning": RunPlan.tuning()}


func test_the_header_records_its_versions_and_inputs() -> void:
	var layouts: LbLayouts = _layouts(4401)
	var plan: Dictionary = layouts.plan(_params())
	assert_true(Variants.flag(plan["ok"]), str(plan["error"]))
	assert_gt(int(Variants.number(plan["generator_version"])), 0, "the generator's version")
	assert_gt(int(Variants.number(plan["hash_version"])), 0, "the hash's version")
	assert_eq(str(plan["template_version"]), layouts.set_version(), "the template pack's set version")
	assert_eq(str(plan["data_version"]), "test-tuning", "the data bundle's version")
	var jobs: PackedStringArray = plan["jobs"]
	assert_eq(Array(jobs), Array(PackedStringArray(STANDARD_JOBS)))
	assert_eq(int(Variants.number(plan["cans"])), 4)
	var draw: PackedStringArray = plan["draw"]
	assert_eq(Array(draw), ["dry_stores"])
	var kinds: Array[String] = []
	for raw: Variant in Variants.array(plan["sites"]):
		kinds.append(str(Variants.dict(raw)["kind"]))
	for kind: String in ["substation", "electricians_cabin", "hoard", "lair", "fitters_shop", "haulage_engine_house", "stores",
			"fuel_store"]:
		assert_true(kinds.has(kind), "a planned %s" % kind)
	assert_eq(Variants.array(plan["spines"]).size(), Variants.array(plan["sites"]).filter(
		func(s: Variant) -> bool: return Variants.flag(Variants.dict(s)["spine"])).size(), "a spine to every site but the spares")


func test_the_bytes_round_trip_exactly() -> void:
	var a: LbLayouts = _layouts(4402)
	var plan: Dictionary = a.plan(_params())
	var bytes: PackedByteArray = a.plan_bytes()
	var in_dict: PackedByteArray = plan["bytes"]
	assert_eq(in_dict, bytes)
	var b: LbLayouts = _layouts(4402)
	assert_true(b.load_plan(bytes))
	assert_eq(b.plan_bytes(), bytes, "byte for byte")
	var again: Dictionary = b.plan_dict()
	var sites_again: Array = again["sites"]
	var sites: Array = plan["sites"]
	assert_eq(sites_again, sites)
	var spines_again: Array = again["spines"]
	var spines: Array = plan["spines"]
	assert_eq(spines_again, spines)
	for raw: Variant in Variants.array(plan["spines"]):
		for c: Vector2i in Variants.array(Variants.dict(raw)["cells"]):
			assert_true(b.is_spine_cell(c), "spine cell %s on the loading deriver" % c)
	# Its sockets too: every spine edge open on both derivers alike.
	var first: Dictionary = Variants.dict(Variants.array(plan["spines"])[0])
	var cells: Array = Variants.array(first["cells"])
	var from: Vector2i = cells[0]
	var to: Vector2i = cells[1]
	var side: String = "east" if to.x > from.x else ("west" if to.x < from.x else ("south" if to.y > from.y else "north"))
	assert_true(Variants.flag(a.socket(from, side)["open"]))
	assert_eq(a.socket(from, side), b.socket(from, side))
	a.set_home("roosts", PackedByteArray([1, 2, 3]))
	assert_eq(a.home("roosts"), PackedByteArray([1, 2, 3]), "GEN-10's and HAZ-01's sections")
	assert_ne(a.plan_bytes(), bytes, "and the header carries them")


func test_another_seeds_header_or_not_a_header_is_refused() -> void:
	var a: LbLayouts = _layouts(4403)
	a.plan(_params())
	var other: LbLayouts = _layouts(4404)
	assert_false(other.load_plan(a.plan_bytes()))
	assert_engine_error("another seed's")
	assert_false(other.load_plan(PackedByteArray([1, 2, 3])))
	assert_engine_error("not a run header")
	assert_true(Variants.array(other.plan_dict()["sites"]).is_empty(), "nothing changed")


func test_run_plan_fixes_the_plan_into_the_run_header() -> void:
	var run: RunState = RunState.new()
	run.header.run_seed = 4405
	run.header.mode = ServerConfig.Mode.FRIENDS
	var layouts: LbLayouts = _road_layouts(4405)
	var plan: Dictionary = RunPlan.fix(layouts, run)
	assert_false(plan.is_empty())
	assert_eq(run.header.plan, layouts.plan_bytes())
	# Every snapshot keeps it (NET-09).
	var head: Dictionary = Snapshot.run_header(Snapshot.capture(run, null))
	var kept: PackedByteArray = head["plan"]
	assert_eq(kept, run.header.plan, "the snapshot's run header holds the plan")
	# A resumed run restores its plan instead of planning again.
	var resumed: RunState = RunState.new()
	resumed.header.run_seed = 4405
	var again: LbLayouts = _road_layouts(4405)
	assert_false(RunPlan.fix(again, resumed, run.header.plan).is_empty())
	assert_eq(again.plan_bytes(), run.header.plan)
	assert_eq(resumed.header.plan, run.header.plan)
