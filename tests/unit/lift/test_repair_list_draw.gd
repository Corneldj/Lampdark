extends GutTest
## LFT-03: the repair list's draw (Gameplay §3.3, §A.6) is one pure function of the seed: the same
## lists on every platform (golden values for 20 seeds, which the round's Wine run checks too).
## Over 10,000 seeds Short is always Power, Fuel, Start; Standard has 5 jobs and Full 7, with 2 or
## 4 distinct pool jobs, Start always last; each pool job comes in a third of Standard lists and two
## thirds of Full; a solo list never draws the drum gear; Fuel needs 2, 4 or 6 cans; the cage is
## wedged exactly when Free the cage is drawn; and with cut 11 Full cannot be drawn.

const SEEDS: int = 10000
## Seeds 1-20's Standard, Full and solo Full lists are in tests/fixtures/lift/repair_lists_golden.json.


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_each() -> void:
	Tuning.clear_dev_overrides()


func _pool(l: RepairList) -> Array[StringName]:
	var out: Array[StringName] = []
	for job: StringName in l.jobs:
		if RepairJobs.POOL.has(job):
			out.append(job)
	return out


func _names(l: RepairList) -> String:
	var out: PackedStringArray = PackedStringArray()
	for job: StringName in l.jobs:
		out.append(String(job))
	return ",".join(out)


func test_the_draw_is_pure_and_matches_its_golden_lists() -> void:
	var got: Dictionary = {}
	for s: int in range(1, 21):
		var a: RepairList = RepairList.for_run(s, RepairList.Kind.STANDARD, false)
		var b: RepairList = RepairList.for_run(s, RepairList.Kind.STANDARD, false)
		assert_eq(_names(a), _names(b), "seed %d: the same list twice" % s)
		got[s] = [_names(a), _names(RepairList.for_run(s, RepairList.Kind.FULL, false)),
			_names(RepairList.for_run(s, RepairList.Kind.FULL, true))]
	var golden: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lift/repair_lists_golden.json")))
	for s: int in range(1, 21):
		var want: Array = Variants.array(golden.get(str(s), []))
		var have: Array = got[s]
		assert_eq(have, want, "seed %d's lists as on every platform" % s)


func test_ten_thousand_seeds_keep_the_shape() -> void:
	for kind: RepairList.Kind in [RepairList.Kind.SHORT, RepairList.Kind.STANDARD, RepairList.Kind.FULL]:
		var want_jobs: int = 3 + RepairList.pool_jobs(kind)
		var bad: int = 0
		for s: int in SEEDS:
			var l: RepairList = RepairList.for_run(s * 7919 + 11, kind, false)
			var pool: Array[StringName] = _pool(l)
			var distinct: Dictionary = {}
			for job: StringName in pool:
				distinct[job] = true
			if l.jobs.size() != want_jobs or distinct.size() != RepairList.pool_jobs(kind) or l.jobs[l.jobs.size() - 1] != &"start" \
					or l.jobs[0] != &"power" or l.jobs[1] != &"fuel" or l.cans_required != RepairList.cans_for(kind) \
					or l.cage_wedged != l.jobs.has(&"free_cage"):
				bad += 1
		assert_eq(bad, 0, "%s: every list the right shape" % RepairJobs.KIND_NAMES[kind])
	var short: RepairList = RepairList.for_run(42, RepairList.Kind.SHORT, false)
	assert_eq(_names(short), "power,fuel,start")
	assert_eq([RepairList.cans_for(RepairList.Kind.SHORT), RepairList.cans_for(RepairList.Kind.STANDARD), RepairList.cans_for(RepairList.Kind.FULL)],
		[2, 4, 6])


func test_each_pool_job_comes_as_often_as_the_others() -> void:
	for case: Array in [[RepairList.Kind.STANDARD, 1.0 / 3.0], [RepairList.Kind.FULL, 2.0 / 3.0]]:
		var kind: RepairList.Kind = int(Variants.number(case[0])) as RepairList.Kind
		var share: float = float(Variants.number(case[1]))
		var counts: Dictionary = {}
		for s: int in SEEDS:
			for job: StringName in _pool(RepairList.for_run(s * 104729 + 3, kind, false)):
				counts[job] = int(Variants.number(counts.get(job, 0))) + 1
		for job: StringName in RepairJobs.POOL:
			var got: float = int(Variants.number(counts.get(job, 0))) / float(SEEDS)
			gut.p("%s: %s in %.1f%% of lists" % [RepairJobs.KIND_NAMES[kind], job, got * 100.0])
			assert_almost_eq(got, share, 0.015, "%s %s" % [RepairJobs.KIND_NAMES[kind], job])


func test_a_solo_list_never_draws_the_drum_gear() -> void:
	for kind: RepairList.Kind in [RepairList.Kind.STANDARD, RepairList.Kind.FULL]:
		var drawn: int = 0
		for s: int in SEEDS:
			if RepairList.for_run(s + 500000, kind, true).has(&"drum_gear"):
				drawn += 1
		assert_eq(drawn, 0, "%s solo: never the drum gear" % RepairJobs.KIND_NAMES[kind])
	assert_true(RepairList.for_run(9, RepairList.Kind.FULL, true).jobs.size() == 7, "a solo Full still draws four")


func test_with_cut_11_full_cannot_be_drawn() -> void:
	assert_eq(Tuning.set_dev_override("lift.full_list_enabled", false), [] as Array[String])
	assert_null(RepairList.for_run(1, RepairList.Kind.FULL, false), "no Full list while it is cut")
	assert_push_error("the Full list is cut")
	assert_not_null(RepairList.for_run(1, RepairList.Kind.STANDARD, false), "Standard still draws")
