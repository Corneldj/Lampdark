extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-05's AloneRules.is_alone: solo, the lone human, and its end the tick a second human comes
## round or rejoins.

const C = preload("res://tests/scenario/director/crew_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_friends_of_three_two_down_third_not_alone() -> void:
	var s: Scenario = make({"seed": 21, "fixture": C.hall()})
	var ids: Array[int] = C.crew(s, ["ann", "bob", "cid"] as Array[String])
	s.step(1)
	C.down(s, ids[0])
	C.down(s, ids[1])
	s.step(2)
	assert_false(AloneRules.is_alone(s.run, ids[2]), "began with three: not a lone human")


func test_friends_of_two_and_a_revive() -> void:
	var s: Scenario = make({"seed": 22, "fixture": C.hall()})
	var ids: Array[int] = C.crew(s, ["ann", "bob"] as Array[String])
	s.step(1)
	assert_false(AloneRules.is_alone(s.run, ids[0]))
	C.down(s, ids[1])
	s.step(2)
	assert_true(AloneRules.is_alone(s.run, ids[0]), "the last conscious of a crew that began with two")
	assert_false(AloneRules.is_alone(s.run, ids[1]), "the unconscious one is not")
	s.run.miner_state.revive(ids[1], &"medbay")
	s.step(1)
	assert_false(AloneRules.is_alone(s.run, ids[0]), "a second human revived: normal rules that tick")
	assert_eq(s.run.crew.count, 2)


func test_public_and_solo() -> void:
	var s: Scenario = make({"seed": 23, "fixture": C.hall()})
	var ids: Array[int] = C.crew(s, ["ann", "bob", "cid"] as Array[String])
	s.run.crew.lobby = CrewCensus.Lobby.PUBLIC
	s.step(1)
	C.down(s, ids[1])
	C.down(s, ids[2])
	s.step(2)
	assert_true(AloneRules.is_alone(s.run, ids[0]), "public: the only conscious human")
	var solo: Scenario = make({"seed": 24, "fixture": C.hall()})
	var one: Array[int] = C.crew(solo, ["ann"] as Array[String])
	solo.step(1)
	assert_true(AloneRules.is_alone(solo.run, one[0]), "a friends lobby of one is solo")
	assert_true(AloneRules.is_solo(solo.run.crew))
	solo.run.crew.lobby = CrewCensus.Lobby.SOLO
	assert_true(AloneRules.is_alone(solo.run, one[0]), "Night Shift")


func test_a_rejoining_human_ends_it() -> void:
	var s: Scenario = make({"seed": 25, "fixture": C.hall()})
	var ids: Array[int] = C.crew(s, ["ann", "bob"] as Array[String])
	var hands: Dictionary = {ids[1]: true}
	C.providers(s, {}, hands)
	s.run.crew.humans_at_start = 2
	s.step(1)
	assert_true(AloneRules.is_alone(s.run, ids[0]), "Bob dropped: his miner is Hand-driven")
	hands.clear()
	s.step(1)
	assert_false(AloneRules.is_alone(s.run, ids[0]), "Bob rejoined: the same tick")
