extends GutTest
## LFT-03: the run's repair list state (Gameplay §3.3). Jobs are marked done by their tickets; only a
## job on the list counts, once; Start waits for every other job, Power included; the list and what
## is done come back whole from a snapshot.


func before_all() -> void:
	assert_true(Tuning.load_server())


func _state(kind: RepairList.Kind) -> Array:
	var run: RunState = RunState.create(77, ServerConfig.Mode.FRIENDS, false)
	var st: RepairListState = RepairListState.new()
	st.bind(run, null)
	st.set_list(RepairList.for_run(77, kind, false))
	return [run, st]


func test_start_waits_for_every_other_job() -> void:
	var w: Array = _state(RepairList.Kind.STANDARD)
	var run: RunState = w[0]
	var st: RepairListState = w[1]
	var others: Array[StringName] = []
	for job: StringName in st.list.jobs:
		if job != &"start":
			others.append(job)
	assert_eq(others.size(), 4)
	var events: Array[StringName] = []
	st.job_done.connect(func(job: StringName) -> void: events.append(job))
	assert_false(st.can_start())
	assert_false(st.mark_done(run, &"start"), "Start before anything else: refused")
	for i: int in others.size():
		assert_true(st.mark_done(run, others[i]))
		assert_eq(st.can_start(), i == others.size() - 1, "after %d of %d" % [i + 1, others.size()])
	assert_false(st.mark_done(run, others[0]), "a job counts once")
	assert_true(st.mark_done(run, &"start"), "then Start")
	assert_eq(events.size(), 5)


func test_power_is_a_prerequisite_and_off_list_jobs_never_count() -> void:
	var w: Array = _state(RepairList.Kind.SHORT)
	var run: RunState = w[0]
	var st: RepairListState = w[1]
	assert_false(st.mark_done(run, &"magneto"), "not on a Short list")
	assert_true(st.mark_done(run, &"fuel"))
	assert_false(st.can_start(), "Fuel alone: the brake still needs Power")
	assert_true(st.mark_done(run, &"power"))
	assert_true(st.can_start())


func test_the_list_and_what_is_done_survive_a_snapshot() -> void:
	var w: Array = _state(RepairList.Kind.FULL)
	var run: RunState = w[0]
	var st: RepairListState = w[1]
	st.mark_done(run, &"power")
	st.mark_done(run, st.list.jobs[2])
	var saved: Dictionary = st.save_state()
	var back: RepairListState = RepairListState.new()
	back.bind(RunState.create(5, ServerConfig.Mode.PUBLIC, false), null)
	back.load_state(run, saved)
	assert_eq(back.list.to_dict(), st.list.to_dict(), "the same list (not redrawn from another seed)")
	assert_true(back.is_done(&"power"))
	assert_true(back.is_done(st.list.jobs[2]))
	assert_false(back.is_done(&"fuel"))
	assert_eq(RepairListState.default_kind(ServerConfig.Mode.PUBLIC), RepairList.Kind.SHORT, "public is Short")
	assert_eq(RepairListState.default_kind(ServerConfig.Mode.FRIENDS), RepairList.Kind.STANDARD)
