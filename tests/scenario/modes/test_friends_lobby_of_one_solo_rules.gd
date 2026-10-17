extends "res://tests/scenario/kit/scenario_test.gd"
## MOD-03 (Gameplay §13.5, §11.11): a friends lobby with one human at the start plays under the solo
## rules: RSC-09's solo predicate holds, its list never draws the drum gear and its plan is solo; it adds
## Hired Hands only when the host chose them. It is not Night Shift: online, no Bess, and the Full list
## is open to it. With two humans at the start it is not solo, and a friend joining later never makes
## a lobby of one into a crew that began with two.


func before_all() -> void:
	assert_true(Tuning.load_server())


func _friends(list: RunOptions.List, hands: bool = false) -> RunOptions:
	var o: RunOptions = RunOptions.defaults(ServerConfig.Mode.FRIENDS)
	o.list = list
	o.hands_in_empty_places = hands
	return o


func test_one_human_at_the_start_plays_the_solo_rules() -> void:
	var s: Scenario = make({"seed": 5101, "fixture": "test"})
	s.add_miner("ann", Vector2i(2, 1))
	assert_eq(RunSetup.create(s.run, _friends(RunOptions.List.FULL), 1, [9] as Array[int]), "", "an Old Hand alone")
	var flags: Dictionary = s.run.header.rule_flags
	assert_true(Variants.flag(flags["solo_rules"]), "a friends lobby of one: the solo rules")
	assert_false(Variants.flag(flags["hands_fill"]), "no Hands: the host did not choose them")
	assert_true(Variants.flag(flags["saved"]), "a friends run is saved")
	assert_false(Variants.flag(flags["public"]))
	s.step(3)
	assert_eq(s.run.crew.humans_at_start, 1, "the census takes the header's humans at the start")
	assert_true(AloneRules.is_solo(s.run.crew), "RSC-09's solo rules apply")
	assert_eq(s.run.crew.lobby, CrewCensus.Lobby.FRIENDS, "not Night Shift's solo lobby")
	assert_eq(s.run.repair.list.kind, RepairList.Kind.FULL, "the Full list, which Night Shift never plays")
	assert_true(Variants.flag(RunPlan.params(s.run)["solo"]), "the plan is a solo one")
	var excluded: Array[String] = Tuning.list_s(&"lift.solo_excluded_jobs")
	assert_true(excluded.has("drum_gear"))
	for job: String in excluded:
		assert_false(s.run.repair.list.jobs.has(StringName(job)), "no %s on a solo list" % job)
	for run_seed: int in 300:
		var solo: RepairList = RepairList.for_run(run_seed * 7919 + 1, RepairList.Kind.FULL, true)
		assert_false(solo.jobs.has(&"drum_gear"), "seed %d: solo lists never draw the drum gear" % run_seed)
	for id: int in s.run.registry.ids():
		assert_ne(s.run.registry.get_entity(id).kind, WorldIds.EntityKind.BESS, "no Bess outside Night Shift")
	# A friend joins in progress: the crew still began with one.
	s.add_miner("bob", Vector2i(4, 1))
	s.step(3)
	assert_eq(s.run.crew.humans_at_start, 1, "a friend joining later never changes who began")
	assert_eq(s.run.crew.humans(s.run).size(), 2)


func test_hands_only_when_the_host_chose_them() -> void:
	var s: Scenario = make({"seed": 5102, "fixture": "test"})
	s.add_miner("ann", Vector2i(2, 1))
	assert_eq(RunSetup.create(s.run, _friends(RunOptions.List.STANDARD, true), 1, [9] as Array[int]), "")
	assert_true(Variants.flag(s.run.header.rule_flags["solo_rules"]), "still the solo rules")
	assert_true(Variants.flag(s.run.header.rule_flags["hands_fill"]), "with the Hands the host added")


func test_two_humans_at_the_start_are_not_solo() -> void:
	var s: Scenario = make({"seed": 5103, "fixture": "test"})
	s.add_miner("ann", Vector2i(2, 1))
	s.add_miner("bob", Vector2i(4, 1))
	assert_eq(RunSetup.create(s.run, _friends(RunOptions.List.STANDARD), 2, [9, 9] as Array[int]), "")
	assert_false(Variants.flag(s.run.header.rule_flags["solo_rules"]), "two humans at the start: the co-op rules")
	s.step(3)
	assert_eq(s.run.crew.humans_at_start, 2, "RSC-09's 'a friends crew that began with exactly two'")
	assert_false(AloneRules.is_solo(s.run.crew))
	assert_false(Variants.flag(RunPlan.params(s.run)["solo"]))
