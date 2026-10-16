extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-03 in a run (Gameplay §3.3): each run's list is drawn from its seed at the start, Short in a
## public lobby and Standard among friends until MOD-03 chooses, and kept through a save; Start
## counts only once every other job on it is done, Power included.

const S = preload("res://tests/scenario/net/save_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_run_draws_its_list_and_start_comes_last() -> void:
	var s: Scenario = make({"seed": 2601, "fixture": S.B.room()})
	var list: RepairList = s.run.repair.list
	assert_eq(list.kind, RepairList.Kind.STANDARD, "friends: Standard until MOD-03 chooses")
	assert_eq(list.to_dict(), RepairList.for_run(s.run.header.run_seed, RepairList.Kind.STANDARD, false).to_dict(), "from the run seed")
	for job: StringName in list.jobs:
		if job != &"start":
			assert_false(s.run.repair.mark_done(s.run, &"start"), "Start waits while %s is not done" % job)
			assert_true(s.run.repair.mark_done(s.run, job))
	assert_true(s.run.repair.mark_done(s.run, &"start"), "every other job done: Start")
	var p: Scenario = make({"seed": 2602, "fixture": S.B.room(), "mode": ServerConfig.Mode.PUBLIC})
	assert_eq(p.run.repair.list.kind, RepairList.Kind.SHORT, "public: Short")


func test_the_list_and_its_progress_come_back_after_a_knock_off() -> void:
	S.clear(2603)
	var s: Scenario = make(S.cfg(2603))
	S.miner(s, "ann", Vector2i(3, 3))
	s.step(5)
	var list: Dictionary = s.run.repair.list.to_dict()
	s.run.repair.mark_done(s.run, &"power")
	s.run.saves.knockoff(s.run)
	s.run.saves.flush()
	var path: String = s.run.saves.run_dir().path_join(Saves.KNOCKOFF_FILE)
	S.kill(s)
	var b: Scenario = S.resume(make, 2603, path)[0]
	assert_eq(b.run.repair.list.to_dict(), list, "the same list")
	assert_true(b.run.repair.is_done(&"power"), "and what was done")
	assert_false(b.run.repair.can_start())
