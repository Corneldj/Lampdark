extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-05's cap: capacity by crew count; a third commit refused at crew count 1 until a place
## frees; a falling count stands nobody down; laying, homing and collecting hold no place.

const C = preload("res://tests/scenario/director/crew_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())
	Tuning.set_dev_override("creatures.enabled", {"moth": 1, "tapper": 1, "stythe": 1})


func after_all() -> void:
	Tuning.clear_dev_overrides()


func test_capacity() -> void:
	for pair: Array in [[0, 2], [1, 2], [2, 3], [3, 3], [5, 3], [9, 3]]:
		var crew_count: int = pair[0]
		var want: int = pair[1]
		assert_eq(ActiveCap.capacity_for(crew_count), want, "crew count %d" % crew_count)


func _three(s: Scenario) -> Array[Creature]:
	s.place_stand_in(WorldIds.EntityKind.MOTH, Vector2i(2, 2))
	s.place_stand_in(WorldIds.EntityKind.TAPPER, Vector2i(4, 2))
	s.place_stand_in(WorldIds.EntityKind.STYTHE, Vector2i(6, 2))
	var out: Array[Creature] = []
	for k: WorldIds.EntityKind in [WorldIds.EntityKind.MOTH, WorldIds.EntityKind.TAPPER, WorldIds.EntityKind.STYTHE]:
		out.append(s.run.creatures.creature_of_kind(k))
	return out


func test_third_commit_waits_at_crew_count_one() -> void:
	var s: Scenario = make({"seed": 31, "fixture": C.hall()})
	var ids: Array[int] = C.crew(s, ["ann"] as Array[String])
	var cs: Array[Creature] = _three(s)
	s.step(2)
	assert_eq(s.run.crew.count, 1)
	var gate: HuntGate = s.run.creatures.gate
	assert_true(gate.request_commit(s.run, cs[0], ids[0], true))
	assert_true(gate.request_commit(s.run, cs[1], ids[0], false))
	for i: int in 10:
		assert_false(gate.request_commit(s.run, cs[2], ids[0], false), "refused every tick while two are active")
		s.step(1)
	gate.stand_down(s.run, cs[0], "lost them")
	assert_true(gate.request_commit(s.run, cs[2], ids[0], false), "then the next attempt succeeds")


func test_a_falling_count_stands_none_down() -> void:
	var s: Scenario = make({"seed": 32, "fixture": C.hall()})
	var ids: Array[int] = C.crew(s, ["ann", "bob"] as Array[String])
	var cs: Array[Creature] = _three(s)
	s.step(2)
	assert_eq(s.run.cap.capacity(), 3)
	var gate: HuntGate = s.run.creatures.gate
	for c: Creature in cs:
		assert_true(gate.request_commit(s.run, c, ids[0], false))
	C.down(s, ids[1])
	s.step(2)
	assert_eq(s.run.crew.count, 1)
	assert_eq(s.run.cap.capacity(), 2)
	for c: Creature in cs:
		assert_true(gate.is_hunting(c), "nobody stood down")
	gate.stand_down(s.run, cs[0], "lost them")
	assert_false(gate.request_commit(s.run, cs[0], ids[0], false), "two still active: it waits")
	gate.stand_down(s.run, cs[1], "lost them")
	assert_true(gate.request_commit(s.run, cs[0], ids[0], false), "fewer than two: a place")


func test_laying_homing_collecting_hold_no_place() -> void:
	var s: Scenario = make({"seed": 33, "fixture": C.hall()})
	C.crew(s, ["ann"] as Array[String])
	var cs: Array[Creature] = _three(s)
	s.step(2)
	for c: Creature in cs:
		c.enter(s.run, &"carry")
	assert_eq(s.run.cap.active_count(), 0, "a laying, homing or collecting state fills no place")
	assert_true(s.run.cap.has_place())
	cs[0].enter(s.run, &"hunt")
	assert_eq(s.run.cap.active_count(), 1)
