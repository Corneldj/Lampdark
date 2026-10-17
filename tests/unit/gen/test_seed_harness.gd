extends GutTest
## GEN-14: the seed harness's command line end to end on the fixture road pack (GEN-07's roads, a
## hub and a plain fallback per biome): every run planned as a server plans it, the gates, the
## report's three files, the same canonical bytes on one thread or many, a gate's failure in the
## exit code (and only reported with --gates report), and a run's repro dump.

const Specs = preload("res://tests/unit/gen/template_specs.gd")
const Main = preload("res://tools/seed_harness/harness_main.gd")

const PACK: String = "user://gen14_road_pack.lbtp"
const OUT: String = "user://gen14_harness"


func before_all() -> void:
	assert_true(Tuning.load_server())
	var problems: Array[String] = []
	var f: FileAccess = FileAccess.open(PACK, FileAccess.WRITE)
	f.store_buffer(Specs.road_pack(problems))
	f.close()
	assert_eq(problems, [] as Array[String])


func _gates(report: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for raw: Variant in Variants.array(report["gates"]):
		var g: Dictionary = Variants.dict(raw)
		out[str(g["name"])] = Variants.flag(g["failed"])
	return out


func test_the_command_line_reports_and_passes_on_the_road_pack() -> void:
	var code: int = Main.main(PackedStringArray(["--seeds", "3", "--lists", "short,standard", "--pack", PACK, "--report", OUT, "--threads", "2"]))
	var text: String = FileAccess.get_file_as_string(OUT.path_join("report.json"))
	var report: Dictionary = Variants.dict(JSON.parse_string(text))
	assert_false(report.is_empty(), "report.json written")
	assert_eq(int(Variants.number(report["runs"])), 6, "3 seeds x 2 lists")
	var gates: Dictionary = _gates(report)
	for name: String in ["plan", "spine_reach", "order", "validator", "fallback_rate", "road_ratio", "joined"]:
		assert_true(gates.has(name), "the %s gate" % name)
		assert_false(Variants.flag(gates.get(name, true)), "%s passes on the road pack" % name)
	assert_eq(code, 0, "no gate failed: exit 0")
	assert_true(FileAccess.file_exists(OUT.path_join("timing.json")), "timing.json written")
	assert_true(FileAccess.get_file_as_string(OUT.path_join("report.md")).begins_with("# Seed harness report"), "report.md written")
	assert_false(text.contains("timing_us"), "the canonical report holds no timing")


func test_one_thread_or_many_give_the_same_canonical_bytes() -> void:
	var base: LbLayouts = MineLayouts.for_run(0, "", PACK)
	assert_not_null(base)
	var runs: Array = []
	for run_seed: int in [5, 6]:
		for kind: int in [RepairList.Kind.STANDARD, RepairList.Kind.FULL]:
			runs.append(Main._run_inputs(run_seed, kind, ""))
	var params: Dictionary = MineLayouts.harness_params("local")
	params["order_cells"] = 80
	var options: Dictionary = {"plan_tuning": RunPlan.tuning(), "params": params, "first_seed": 5, "last_seed": 6, "lists": [1, 2], "progress_s": 0.0}
	options["threads"] = 1
	var one: Dictionary = LbSeedHarness.run(base, MineLayouts.configure_params(0), runs, options)
	options["threads"] = 4
	var many: Dictionary = LbSeedHarness.run(base, MineLayouts.configure_params(0), runs, options)
	assert_eq(int(Variants.number(one["threads"])), 1)
	assert_eq(int(Variants.number(many["threads"])), 4)
	assert_eq(str(one["json"]), str(many["json"]), "byte-identical, timing aside")


func test_a_failed_gate_fails_the_exit_code_unless_only_reported() -> void:
	# The shipped set (one template, no fallback) cannot generate a mine yet: GEN-16's content.
	var failing: PackedStringArray = PackedStringArray(["--seeds", "1", "--lists", "standard", "--report", OUT.path_join("shipped")])
	assert_eq(Main.main(failing), 1, "a gate failed")
	failing.append_array(["--gates", "report"])
	assert_eq(Main.main(failing), 0, "reported, not enforced")
	assert_eq(Main.main(PackedStringArray(["--lists", "nowhere"])), 2, "a bad argument")


func test_a_runs_repro_dump_names_it_and_draws_the_cell() -> void:
	var base: LbLayouts = MineLayouts.for_run(0, "", PACK)
	var options: Dictionary = {"plan_tuning": RunPlan.tuning(), "params": MineLayouts.harness_params("local")}
	var text: String = LbSeedHarness.repro(base, MineLayouts.configure_params(0), Main._run_inputs(4, RepairList.Kind.STANDARD, ""), options, "", Vector2i(2, -1))
	assert_true(text.begins_with("seed 4, list standard, check all"), text.substr(0, 80))
	assert_true(text.contains("cell (2, -1): template "), "the cell's template")
	assert_true(text.contains("phase 2: retry "), "phase 2's account")
	assert_true(text.contains("order 2: digest "), "its digest in each order")
	var rows: int = 0
	for line: String in text.split("\n"):
		if line.length() == 22 and line.begins_with("  ") and not line.substr(2).contains(" "):
			rows += 1
	assert_eq(rows, 20, "its 20 rows of tiles")
