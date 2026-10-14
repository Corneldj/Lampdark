extends GutTest
## QA-01 criterion 5's A/B harness: a balanced, blind, reproducible plan per tester (20 trials per
## condition; half north, half south; half tone, half footstep), the two conditions interleaved, the
## codes' meaning drawn per tester; and a scripted run of the harness writes a results file that
## listener_ab_report.py pools and judges.

const Plan = preload("res://tools/kill_test/listener_ab/listener_ab_plan.gd")
const Harness = preload("res://tools/kill_test/listener_ab/listener_ab.gd")


func before_all() -> void:
	assert_true(Tuning.load_client())


func test_balanced_and_reproducible() -> void:
	var p: Dictionary = Plan.make(42)
	var trials: Array = p["trials"]
	assert_eq(trials.size(), 40)
	for condition: String in Plan.CONDITIONS:
		var mine: Array = trials.filter(func(t: Dictionary) -> bool: return str(t["condition"]) == condition)
		assert_eq(mine.size(), 20, condition)
		assert_eq(mine.filter(func(t: Dictionary) -> bool: return str(t["source"]) == "north").size(), 10, "%s: half north" % condition)
		assert_eq(mine.filter(func(t: Dictionary) -> bool: return str(t["sound"]) == "tone").size(), 10, "%s: half tones" % condition)
	assert_eq(JSON.stringify(Plan.make(42)), JSON.stringify(p), "the same seed, the same plan")
	assert_ne(JSON.stringify(Plan.make(43)["trials"]), JSON.stringify(trials), "another tester, another order")


func test_interleaved_and_blind() -> void:
	var p: Dictionary = Plan.make(7)
	var switches: int = 0
	var trials: Array = p["trials"]
	for i: int in range(1, trials.size()):
		if str(Variants.dict(trials[i])["code"]) != str(Variants.dict(trials[i - 1])["code"]):
			switches += 1
	assert_gt(switches, 10, "conditions shuffled together, not in blocks")
	for t: Variant in trials:
		var shown: String = Plan.shown(Variants.dict(t))
		assert_false(shown.contains("facing") or shown.contains("screen"), "the screen shows only a code: %s" % shown)
	var a_facing: int = 0
	for seed_value: int in 200:
		if str(Variants.dict(Plan.make(seed_value)["codes"])["A"]) == "facing":
			a_facing += 1
	assert_between(a_facing, 70, 130, "A means facing for about half the testers")


func test_a_scripted_run_writes_results_the_report_judges() -> void:
	var dir: String = "user://test_listener_ab_%d" % Time.get_ticks_usec()
	var h: Node = Harness.new()
	h.set(&"tester", "T99")
	h.set(&"seed_value", 99)
	h.set(&"out_dir", dir)
	# Right every time with the facing-relative ears, a coin toss with screen-up.
	h.set(&"auto_answer", func(t: Dictionary) -> String:
		var truth: String = "N" if str(t["source"]) == "north" else "S"
		if str(t["condition"]) == "facing" or int(Variants.number(t["index"])) % 2 == 0:
			return truth
		return "S" if truth == "N" else "N")
	var done: Array[String] = []
	h.connect(&"finished", func(path: String) -> void: done.append(path))
	add_child_autofree(h)
	var waited: int = 0
	while done.is_empty() and waited < 300:
		await get_tree().process_frame
		waited += 1
	assert_eq(done.size(), 1, "all 40 trials answered")
	var lines: PackedStringArray = FileAccess.get_file_as_string(done[0]).strip_edges().split("\n")
	assert_eq(lines.size(), 41, "a header and 40 answers")
	var head: Dictionary = Variants.dict(JSON.parse_string(lines[0]))
	assert_true(head.has("codes"), "the codes' meaning is in the file, for the analysis")
	if OS.get_name() == "Windows":
		# No python3 on Windows or under Wine: the report's own tests are test_listener_ab_report.py.
		gut.p("Windows: the file is checked here; the report is tested in Python")
		DirAccess.remove_absolute(done[0])
		DirAccess.remove_absolute(dir)
		return
	var out: Array = []
	var code: int = OS.execute("python3", PackedStringArray([ProjectSettings.globalize_path("res://tools/kill_test/listener_ab_report.py"),
		"--json", done[0]]), out, true)
	assert_eq(code, 0, "the report passes this tester: %s" % [out])
	var report: Dictionary = Variants.dict(JSON.parse_string("".join(PackedStringArray(out))))
	var facing: Dictionary = Variants.dict(Variants.dict(report["headphones"])["facing"])
	assert_eq(int(Variants.number(facing["correct"])), 20)
	DirAccess.remove_absolute(done[0])
	DirAccess.remove_absolute(dir)
