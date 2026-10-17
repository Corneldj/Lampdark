extends GutTest
## GEN-12: the validator through LbLayouts. A cell's final layout is the reroll phase 1 accepted
## (derive_final, what generation commits); at run start every spine walks to its target and base
## camp's gates hold (validate_run_start); placements pass phase 2 (placement_report); the counts
## stay on the server (validator_stats); and every plain fallback a pack carries covers every
## socket set at every width its biome allows (fallback_coverage), the shipped pack's included.

const Specs = preload("res://tests/unit/gen/template_specs.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _layouts(run_seed: int, pack: PackedByteArray) -> LbLayouts:
	var layouts: LbLayouts = LbLayouts.new()
	assert_true(layouts.load_pack(pack))
	MineLayouts.configure(layouts, run_seed)
	return layouts


func _plan_params(kind: int, jobs: Array[String]) -> Dictionary:
	return {"list_kind": kind, "jobs": PackedStringArray(jobs), "cans": RepairList.cans_for(kind as RepairList.Kind),
		"solo": false, "draw": PackedStringArray(), "staging": "", "hard_variant": "", "data_version": "",
		"tuning": RunPlan.tuning()}


## The widths a socket can take in `biome`: every socket width up to the biome's maximum.
static func _widths(biome: String) -> PackedInt32Array:
	var hi: Dictionary = Tuning.table(&"mine.biome_socket_widths_max")
	var top: int = int(Variants.number(hi.get(biome, 3)))
	var out: PackedInt32Array = PackedInt32Array()
	for w: int in Tuning.list_i(&"mine.socket_widths_tiles"):
		if w <= top:
			out.append(w)
	return out


func test_a_cells_final_layout_is_the_reroll_phase_one_accepted() -> void:
	var problems: Array[String] = []
	var layouts: LbLayouts = _layouts(7919, Specs.road_pack(problems))
	assert_eq(problems.size(), 0, str(problems.slice(0, 3)))
	var cells: int = 0
	for y: int in range(-4, 5):
		for x: int in range(-4, 5):
			var c: Vector2i = Vector2i(x, y)
			var final: Dictionary = layouts.derive_final(c)
			assert_true(Variants.flag(final["ok"]), "%s has a layout" % c)
			var reroll: int = int(Variants.number(final["reroll"]))
			var raw: Dictionary = layouts.derive(c, reroll)
			assert_eq(Variants.whole(final["digest"]), Variants.whole(raw["digest"]), "%s: the final layout is reroll %d's" % [c, reroll])
			var tries: Array = Variants.array(final["tries"])
			assert_eq(tries.size(), reroll, "%s: one failed try before each reroll" % c)
			if c != Vector2i.ZERO:
				cells += 1
	var totals: Dictionary = Variants.dict(layouts.validator_stats()["totals"])
	assert_eq(int(Variants.number(totals.get("cells", 0))), cells, "each cell counted once")
	assert_false(totals.has("shipped_invalid"))


func test_run_start_walks_every_spine_and_checks_the_gates() -> void:
	var problems: Array[String] = []
	var pack: PackedByteArray = Specs.road_pack(problems)
	var walked: int = 0
	for i: int in 4:
		var run_seed: int = 6007 * (i + 2)
		var layouts: LbLayouts = _layouts(run_seed, pack)
		var plan: Dictionary = layouts.plan(_plan_params(RepairList.Kind.STANDARD, ["power", "fuel", "magneto", "brake_shoes", "start"]))
		assert_true(Variants.flag(plan["ok"]), str(plan["error"]))
		var before: PackedByteArray = layouts.plan_bytes()
		var report: Dictionary = layouts.validate_run_start()
		assert_true(Variants.flag(report["ok"]), str(report))
		var spines: Array = Variants.array(report["spines"])
		assert_eq(spines.size(), Variants.array(plan["spines"]).size())
		for raw: Variant in spines:
			var spine: Dictionary = raw
			assert_true(Variants.flag(spine["reached"]), str(spine))
			walked += 1
		assert_true(Variants.flag(Variants.dict(report["gates"])["ok"]))
		assert_eq(int(Variants.number(report["replans"])), 0, "nothing to replan on the road pack")
		assert_eq(layouts.plan_bytes(), before, "an unreplanned plan keeps its bytes")
		var totals: Dictionary = Variants.dict(layouts.validator_stats()["totals"])
		assert_eq(int(Variants.number(totals.get("spines", 0))), spines.size())
		assert_false(totals.has("spines_unreached"))
		assert_false(totals.has("gates_failed"))
	assert_gt(walked, 12)


func test_placements_pass_phase_two() -> void:
	var problems: Array[String] = []
	var layouts: LbLayouts = _layouts(4217, Specs.road_pack(problems))
	layouts.plan(_plan_params(RepairList.Kind.STANDARD, ["power", "fuel", "magneto", "brake_shoes", "start"]))
	layouts.validate_run_start()
	layouts.make_homes()
	for y: int in range(-3, 4):
		for x: int in range(-3, 4):
			var c: Vector2i = Vector2i(x, y)
			var report: Dictionary = layouts.placement_report(c)
			assert_eq(Variants.array(report["failures"]).size(), 0, "%s: %s" % [c, str(report["failures"])])
			assert_false(Variants.flag(report["strict"]))
			layouts.place(c)
	var totals: Dictionary = Variants.dict(layouts.validator_stats()["totals"])
	assert_eq(int(Variants.number(totals.get("placed", 0))), 48, "each placed cell counted once (base camp places nothing)")
	assert_false(totals.has("strict"))


func test_every_plain_fallback_covers_every_socket_set() -> void:
	var problems: Array[String] = []
	var road: LbLayouts = _layouts(1, Specs.road_pack(problems))
	for biome: String in ["pit_bottom", "seam", "old_workings", "black_seam", "old_mens"]:
		var coverage: Dictionary = road.fallback_coverage(biome, _widths(biome))
		var states: int = 1 + 3 * _widths(biome).size() # shut, or open at 5, 10 or 15 at each width
		assert_eq(int(Variants.number(coverage["checked"])), states * states * states * states, biome)
		assert_eq(Variants.array(coverage["failures"]).size(), 0, "%s: %s" % [biome, str(Variants.array(coverage["failures"]).slice(0, 2))])
	# The shipped pack: every fallback it carries (GEN-16 ships one for every biome).
	var shipped: LbLayouts = MineLayouts.for_run(1)
	assert_not_null(shipped)
	var current: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string("res://data/templates/set.json")))
	var decoded: Dictionary = LbTemplates.decode_pack(FileAccess.get_file_as_bytes("res://data/templates/%s" % str(current["pack"])))
	var missing: Array[String] = []
	for biome: String in Variants.dict(Tuning.table(&"mine.biome_socket_widths_max")).keys():
		if biome == "main_road":
			continue # a main road falls back to the biome it crosses (GEN-07)
		var has_fallback: bool = false
		for raw: Variant in Variants.array(decoded.get("templates", [])):
			var t: Dictionary = raw
			has_fallback = has_fallback or (str(t["kind"]) == "fallback" and str(t["biome"]) == biome)
		if not has_fallback:
			missing.append(biome)
			continue
		var coverage: Dictionary = shipped.fallback_coverage(biome, _widths(biome))
		assert_eq(Variants.array(coverage["failures"]).size(), 0, "shipped %s: %s" % [biome, str(Variants.array(coverage["failures"]).slice(0, 2))])
	if not missing.is_empty():
		gut.p("GEN-16 to come: no plain fallback yet in the shipped pack for %s" % ", ".join(missing))


func test_base_camps_arches_reach_into_its_gate_cells() -> void:
	var length: int = roundi(Tuning.f(&"basecamp.arch_length_tiles"))
	for run_seed: int in [1, 2, 3, 4, 5, 6, 7, 8]:
		var reach: Dictionary = Basecamp.arch_reach(run_seed)
		var gates: Array[Dictionary] = Basecamp.gate_specs(run_seed)
		assert_eq(reach.size(), gates.size(), "a reach for each gate")
		for g: Dictionary in gates:
			var r: int = int(Variants.number(reach[str(g["side"])]))
			assert_between(r, 1, length, "seed %d %s" % [run_seed, str(g["side"])])
		var params: Dictionary = MineLayouts.validate_params(run_seed)
		assert_eq(Variants.dict(params["arch_reach"]), reach)
