extends GutTest
## NET-07's budget soak, short: tools/bots/soaks/record_budget_nightly.gd (three hours of five bots
## and 20 falls, FND-04's record nightly slot) run here for three minutes, falls and all. The ring
## cannot fill in three minutes, so only the nightly judges its size; this checks the memory bound,
## that every fall pins a window that seals and replays, and that no keyframe view is missing.

const Accelerated = preload("res://tools/bots/accelerated.gd")
const SOAK: String = "res://tools/bots/soaks/record_budget_nightly.gd"


func test_three_minutes_of_the_record_soak() -> void:
	var script: GDScript = load(SOAK)
	var soak: Object = script.new()
	soak.call(&"setup", {})
	var profile: Dictionary = soak.get(&"profile")
	profile["minutes"] = 3.0
	var brains: Array = profile["brains"]
	var report: Dictionary = {"servers": [], "applied_input_logs": [], "bots": [], "bytes_per_client": {}}
	var ticks: int = roundi(3.0 * 60.0 * 20.0)
	var out_dir: String = "user://net07_record_soak"
	DirAccess.make_dir_recursive_absolute(out_dir)
	Accelerated.run(profile, 1, 5, ticks, out_dir, func(n: int) -> String: return brains[n % brains.size()], report, soak)
	var server: Dictionary = Variants.array(report["servers"])[0]
	var st: Dictionary = server["inspect"]
	gut.p("record: max %.2f MB (ring %.2f MB), windows %.2f MB, %s falls, %s thinned; record system p99 %s us" % [
		float(Variants.number(st["total_max"])) / 1048576.0, float(Variants.number(st["ring_max"])) / 1048576.0,
		float(Variants.number(st["windows_bytes"])) / 1048576.0, st["falls"], st["thinned"], Variants.dict(st["record_usec"]).get("p99")])
	var errors: Array[String] = soak.call(&"verify", report)
	assert_eq(errors, [] as Array[String])
	assert_eq(int(Variants.number(st["falls"])), 20)
	assert_gt(int(Variants.number(st["revived"])), 0)
