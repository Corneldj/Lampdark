extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-05's crew count: every row of the acceptance list.

const C = preload("res://tests/scenario/director/crew_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _count(s: Scenario) -> int:
	s.step(2)
	return s.run.crew.count


func test_four_friends_out() -> void:
	var s: Scenario = make({"seed": 1, "fixture": C.hall()})
	C.crew(s, ["a", "b", "c", "d"] as Array[String])
	assert_eq(_count(s), 4)


func test_one_sealed_inside_then_a_gate_opens() -> void:
	var s: Scenario = make({"seed": 2, "fixture": C.hall()})
	var ids: Array[int] = C.crew(s, ["a", "b", "c", "d"] as Array[String])
	var sealed: Dictionary = {ids[3]: true}
	C.providers(s, sealed, {})
	assert_eq(_count(s), 3, "three out, one inside a sealed base camp")
	sealed.clear()
	assert_eq(_count(s), 4, "a gate opens")


func test_one_of_four_falls() -> void:
	var s: Scenario = make({"seed": 3, "fixture": C.hall()})
	var ids: Array[int] = C.crew(s, ["a", "b", "c", "d"] as Array[String])
	C.down(s, ids[0])
	assert_eq(_count(s), 3)


func test_two_humans_with_hands() -> void:
	for n: int in [1, 2, 3]:
		var s: Scenario = make({"seed": 4 + n, "fixture": C.hall()})
		var names: Array[String] = ["ann", "bob"]
		for i: int in n:
			names.append("hand%d" % i)
		var ids: Array[int] = C.crew(s, names)
		var hands: Dictionary = {}
		for i: int in n:
			hands[ids[2 + i]] = true
		C.providers(s, {}, hands)
		s.run.crew.humans_at_start = 2
		var want: Array[int] = [2, 3, 3]
		assert_eq(_count(s), want[n - 1], "two humans and %d Hands" % n)


func test_public_lone_human_with_three_hands() -> void:
	var s: Scenario = make({"seed": 9, "fixture": C.hall()})
	var ids: Array[int] = C.crew(s, ["ann", "h1", "h2", "h3"] as Array[String])
	C.providers(s, {}, {ids[1]: true, ids[2]: true, ids[3]: true})
	s.run.crew.lobby = CrewCensus.Lobby.PUBLIC
	assert_eq(_count(s), 1)


func test_friends_began_with_two_one_down_two_hands() -> void:
	var s: Scenario = make({"seed": 10, "fixture": C.hall()})
	var ids: Array[int] = C.crew(s, ["ann", "bob", "h1", "h2"] as Array[String])
	C.providers(s, {}, {ids[2]: true, ids[3]: true})
	s.step(1)
	assert_eq(s.run.crew.humans_at_start, 2)
	C.down(s, ids[1])
	assert_eq(_count(s), 1, "a lone human counts 1, whatever the Hands")


func test_recount_signal_only_on_change() -> void:
	var s: Scenario = make({"seed": 11, "fixture": C.hall()})
	var ids: Array[int] = C.crew(s, ["a", "b", "c"] as Array[String])
	s.step(2)
	watch_signals(s.run.crew)
	s.step(5)
	assert_signal_not_emitted(s.run.crew, "crew_count_changed")
	C.down(s, ids[0])
	s.step(2)
	assert_signal_emit_count(s.run.crew, "crew_count_changed", 1)
	var params: Array = get_signal_parameters(s.run.crew, "crew_count_changed")
	assert_eq(params, [3, 2])
