extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-09: in a friends crew that began with two, the last conscious human gets the solo rules (here,
## falling last, the self-revive); in one that began with three, nobody ever does.

const LW = preload("res://tests/unit/rescue/lone_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_the_last_of_a_pair_comes_round() -> void:
	var w: Array = LW.crew(make, 951, ["ann", "bob"])
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1][0]
	var bob: MinerHandle = w[1][1]
	LW.fall(s, ann)
	assert_false(s.run.self_revive.self_revive_pending(ann.entity_id), "Bob was conscious: Ann never arms one")
	assert_true(AloneRules.is_alone(s.run, bob.entity_id), "Bob, the last conscious human")
	LW.fall(s, bob)
	assert_true(s.run.self_revive.self_revive_pending(bob.entity_id), "falling alone, Bob's arms")
	s.step(610)
	assert_eq(LW.life(s, bob), MinerTransitions.Life.UPRIGHT, "Bob comes round")
	assert_eq(LW.life(s, ann), MinerTransitions.Life.UNCONSCIOUS, "Ann does not")


func test_a_crew_of_three_never_plays_them() -> void:
	var w: Array = LW.crew(make, 952, ["ann", "bob", "cat"])
	var s: Scenario = w[0]
	var crew: Array[MinerHandle] = []
	var handles: Array = w[1]
	crew.assign(handles)
	for h: MinerHandle in crew:
		LW.fall(s, h)
		assert_false(AloneRules.is_alone(s.run, crew[2].entity_id) and h != crew[2], "nobody alone")
	s.step(700)
	for h: MinerHandle in crew:
		assert_eq(LW.life(s, h), MinerTransitions.Life.UNCONSCIOUS, "%s stays down" % h.name)
