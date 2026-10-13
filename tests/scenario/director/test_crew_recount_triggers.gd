extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-05: a fall, a coming round, a gate opening and shutting, and a Hand joining and leaving
## each change the crew count on the same tick.

const C = preload("res://tests/scenario/director/crew_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_triggers() -> void:
	var s: Scenario = make({"seed": 51, "fixture": C.hall()})
	var ids: Array[int] = C.crew(s, ["ann", "bob", "cid", "hand"] as Array[String])
	var sealed: Dictionary = {}
	var hands: Dictionary = {ids[3]: true}
	C.providers(s, sealed, hands)
	s.run.crew.humans_at_start = 3
	var changes: Array[Array] = []
	s.run.crew.crew_count_changed.connect(func(old: int, now: int) -> void: changes.append([s.run.tick, old, now]))
	s.step(2)
	changes.clear()
	var events: Array = [
		["a fall", func() -> void: C.down(s, ids[0]), 2],
		["coming round", func() -> void: s.run.miner_state.revive(ids[0], &"medbay"), 3],
		["a gate shuts on Bob in base camp", func() -> void: sealed[ids[1]] = true, 2],
		["the gate opens", func() -> void: sealed.erase(ids[1]), 3],
		["the Hand leaves", func() -> void: hands.erase(ids[3]), 4],
		["a Hand joins", func() -> void: hands[ids[3]] = true, 3],
	]
	for e: Array in events:
		var what: String = e[0]
		var act: Callable = e[1]
		var want: int = e[2]
		var at: int = s.run.tick
		act.call()
		s.step(1)
		assert_eq(s.run.crew.count, want, what)
		assert_eq(changes.size(), 1, "%s: one change" % what)
		if not changes.is_empty():
			var c: Array = changes[0]
			var tick_of: int = c[0]
			assert_lte(tick_of - at, 1, "%s: on the tick it happened" % what)
		changes.clear()
