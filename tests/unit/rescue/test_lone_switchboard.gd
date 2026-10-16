extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-09: every substitution switches on and off together with AloneRules.is_alone, and the alone
## watch says so (`alone_changed`). The matrix: a friends lobby of one; a friends crew that began with
## two (its last conscious human); one that began with three (never); Night Shift; a public lone
## human among Hands. LFT-04's solo jobs are among them; DIR-03's Pull registers only with the
## Director installed.

const LW = preload("res://tests/unit/rescue/lone_world.gd")
const ALL: Array[String] = ["heard_by_companion", "self_rescue", "self_revive", "solo_jobs"]


func before_all() -> void:
	assert_true(Tuning.load_server())


func _subs(s: Scenario, h: MinerHandle) -> Array[String]:
	return s.run.lone.active_substitutions(s.run, h.entity_id)


func test_a_friends_lobby_of_one_and_night_shift_play_the_solo_rules() -> void:
	for mode: ServerConfig.Mode in [ServerConfig.Mode.FRIENDS, ServerConfig.Mode.NIGHTSHIFT]:
		var w: Array = LW.crew(make, 921 + mode, ["ann"], mode)
		var s: Scenario = w[0]
		var ann: MinerHandle = w[1][0]
		assert_true(AloneRules.is_alone(s.run, ann.entity_id), "mode %d: alone" % mode)
		assert_eq(_subs(s, ann), ALL, "mode %d: every substitution on" % mode)


func test_the_last_human_of_a_pair_gets_them_and_loses_them_in_the_same_tick() -> void:
	var w: Array = LW.crew(make, 925, ["ann", "bob"])
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1][0]
	var bob: MinerHandle = w[1][1]
	var changes: Array = []
	s.run.alone_watch.alone_changed.connect(func(m: int, on: bool) -> void: changes.append([m, on, s.run.tick]))
	assert_eq(_subs(s, bob), [] as Array[String], "two conscious: normal rules")
	LW.fall(s, ann)
	s.step(1)
	assert_eq(_subs(s, bob), ALL, "Bob, the last conscious human: every substitution")
	assert_true(changes.any(func(c: Array) -> bool: return c[0] == bob.entity_id and c[1]), "the watch says so")
	s.run.miner_state.revive(ann.entity_id, &"kit")
	s.step(1)
	assert_eq(_subs(s, bob), [] as Array[String], "Ann conscious again: all off together")
	assert_true(changes.any(func(c: Array) -> bool: return c[0] == bob.entity_id and not c[1]))


func test_a_crew_that_began_with_three_never_does() -> void:
	var w: Array = LW.crew(make, 926, ["ann", "bob", "cat"])
	var s: Scenario = w[0]
	var crew: Array[MinerHandle] = []
	var handles: Array = w[1]
	crew.assign(handles)
	LW.fall(s, crew[0])
	LW.fall(s, crew[1])
	s.step(1)
	assert_false(AloneRules.is_alone(s.run, crew[2].entity_id))
	assert_eq(_subs(s, crew[2]), [] as Array[String], "the last of three: never")


func test_a_spent_self_revive_drops_out_of_the_list() -> void:
	var w: Array = LW.crew(make, 927, ["ann"])
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1][0]
	LW.fall(s, ann)
	s.step(610)
	assert_eq(_subs(s, ann), ["heard_by_companion", "self_rescue", "solo_jobs"] as Array[String], "the self-revive spent")
