extends RefCounted
## GEN-14: the seed harness from the command line (run.gd starts it once the tree runs) (Gameplay §12.3, §12.5; GDD §15.9, §C.11). Every
## run in a seed range is planned for each list exactly as a server plans it (MineLayouts' deriver,
## RepairList's draw, RunPlan's inputs, base camp's gates and arches, the validated tuning), checked
## on every core (LbSeedHarness: dev and QA builds), and reported:
## - report.json: canonical, the same bytes for the same seeds, pack and binaries;
## - timing.json: the same with the machine's timing; report.md: for people.
## Exits 1 when a gate fails (with --gates enforce, the default), 2 on bad arguments or no pack.
##
## Usage (tools/seed_harness/run.sh wraps it from the game's root):
##   run.gd -- [--seeds N | A..B] [--lists all | short,standard,full] [--report DIR] [--threads N]
##             [--machine local | ci | fleet | deck] [--pack FILE] [--hard VARIANT]
##             [--gates enforce | report] [--failures N]
##   run.gd -- --repro SEED LIST CHECK [X,Y]
## --seeds N runs seeds 0 to N-1 (default mine.harness_seeds; mine.harness_deck_sample_seeds with
## --machine deck). --machine fleet gates generation time on mine.generation_budget_ms_server (the
## reference machine); deck reports against mine.generation_budget_ms_deck.

const LISTS: Dictionary = {"short": RepairList.Kind.SHORT, "standard": RepairList.Kind.STANDARD, "full": RepairList.Kind.FULL}
const VALUED: Array[String] = ["--seeds", "--lists", "--report", "--threads", "--machine", "--pack", "--hard", "--gates", "--failures"]


static func main(args: PackedStringArray) -> int:
	var opts: Dictionary = {"seeds": "", "lists": "all", "report": "build/seed_harness", "threads": "0", "machine": "local", "pack": "", "hard": "",
		"gates": "enforce", "failures": "40"}
	var repro: PackedStringArray = PackedStringArray()
	var i: int = 0
	while i < args.size():
		var a: String = args[i]
		if a == "--help" or a == "-h":
			print(_usage())
			return 0
		if a == "--repro":
			repro = args.slice(i + 1)
			break
		if not VALUED.has(a) or i + 1 >= args.size():
			printerr("seed harness: %s\n%s" % ["unknown argument " + a if not VALUED.has(a) else a + " needs a value", _usage()])
			return 2
		opts[a.substr(2)] = args[i + 1]
		i += 2
	if not Tuning.load_server():
		printerr("seed harness: the tuning does not load")
		return 2
	var machine: String = str(opts["machine"])
	var base: LbLayouts = MineLayouts.for_run(0, "", str(opts["pack"]))
	if base == null:
		return 2
	var options: Dictionary = {
		"threads": int(str(opts["threads"])),
		"plan_tuning": RunPlan.tuning(),
		"params": MineLayouts.harness_params(machine),
		"progress_s": 30.0,
	}
	Variants.dict(options["params"])["failures_kept_per_check"] = int(str(opts["failures"]))
	var configure: Dictionary = MineLayouts.configure_params(0)
	if not repro.is_empty():
		return _repro(base, configure, options, repro, str(opts["hard"]))
	var seeds: Vector2i = _seed_range(str(opts["seeds"]), machine)
	var lists: Array[int] = _lists(str(opts["lists"]))
	if seeds.y < seeds.x or lists.is_empty():
		printerr("seed harness: no seeds or no lists\n" + _usage())
		return 2
	var runs: Array = []
	for run_seed: int in range(seeds.x, seeds.y + 1):
		for kind: int in lists:
			runs.append(_run_inputs(run_seed, kind, str(opts["hard"])))
	options["first_seed"] = seeds.x
	options["last_seed"] = seeds.y
	options["lists"] = lists
	print("seed harness: %d seeds x %d lists = %d runs on %s, set %s" % [seeds.y - seeds.x + 1, lists.size(), runs.size(), machine, base.set_version()])
	var result: Dictionary = LbSeedHarness.run(base, configure, runs, options)
	if result.is_empty():
		return 2
	var dir: String = str(opts["report"])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir) if dir.contains("://") else dir)
	_write(dir.path_join("report.json"), str(result["json"]))
	_write(dir.path_join("timing.json"), str(result["timing_json"]))
	_write(dir.path_join("report.md"), str(result["markdown"]))
	for raw: Variant in Variants.array(result["gates"]):
		var g: Dictionary = Variants.dict(raw)
		print("  %-16s %s  %s" % [str(g["name"]), "FAIL" if Variants.flag(g["failed"]) else "pass", str(g["detail"])])
	print("seed harness: %d runs in %.1f s on %d threads; the report is in %s" % [int(Variants.number(result["runs"])),
		float(Variants.number(result["seconds"])), int(Variants.number(result["threads"])), dir])
	var failed: bool = Variants.flag(result["failed"])
	if failed:
		print("seed harness: a gate FAILED%s" % ("" if str(opts["gates"]) == "enforce" else " (reported, not enforced)"))
	return 1 if failed and str(opts["gates"]) == "enforce" else 0


## A run's inputs as RunSetup and RunPlan make them: its list drawn from its seed (friends' rules, not
## solo), its base camp's gates and arches, the tuning's version.
static func _run_inputs(run_seed: int, kind: int, hard: String) -> Dictionary:
	var list: RepairList = RepairList.for_run(run_seed, kind as RepairList.Kind, false)
	var run: Dictionary = RunPlan.inputs_of(list, false, PackedStringArray(), "", hard, Tuning.content_hash())
	run["seed"] = run_seed
	run["gates"] = Basecamp.gate_sockets(run_seed)
	run["arch_reach"] = Basecamp.arch_reach(run_seed)
	return run


static func _repro(base: LbLayouts, configure: Dictionary, options: Dictionary, args: PackedStringArray, hard: String) -> int:
	if args.size() < 3 or not args[0].is_valid_int() or not LISTS.has(args[1]):
		printerr("seed harness: --repro SEED LIST CHECK [X,Y]\n" + _usage())
		return 2
	var cell: Variant = null
	if args.size() >= 4:
		var xy: PackedStringArray = args[3].split(",")
		if xy.size() != 2 or not xy[0].is_valid_int() or not xy[1].is_valid_int():
			printerr("seed harness: a cell is X,Y")
			return 2
		cell = Vector2i(int(xy[0]), int(xy[1]))
	var run: Dictionary = _run_inputs(int(args[0]), int(Variants.number(LISTS[args[1]])), hard)
	print(LbSeedHarness.repro(base, configure, run, options, args[2], cell))
	return 0


static func _seed_range(text: String, machine: String) -> Vector2i:
	if text.is_empty():
		var n: int = Tuning.i(&"mine.harness_deck_sample_seeds") if machine == "deck" else Tuning.i(&"mine.harness_seeds")
		return Vector2i(0, n - 1)
	if text.contains(".."):
		var parts: PackedStringArray = text.split("..")
		if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			return Vector2i(int(parts[0]), int(parts[1]))
		return Vector2i(0, -1)
	return Vector2i(0, int(text) - 1) if text.is_valid_int() else Vector2i(0, -1)


static func _lists(text: String) -> Array[int]:
	var out: Array[int] = []
	if text == "all":
		out.assign([RepairList.Kind.SHORT, RepairList.Kind.STANDARD, RepairList.Kind.FULL])
		return out
	for name: String in text.split(","):
		if not LISTS.has(name):
			return [] as Array[int]
		out.append(int(Variants.number(LISTS[name])))
	return out


static func _write(path: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("seed harness: cannot write %s" % path)
		return
	f.store_string(text)
	f.close()


static func _usage() -> String:
	return "usage: run.sh [--seeds N|A..B] [--lists all|short,standard,full] [--report DIR] [--threads N] [--machine local|ci|fleet|deck]" \
		+ " [--pack FILE] [--hard VARIANT] [--gates enforce|report] [--failures N] | --repro SEED LIST CHECK [X,Y]"
