extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-05: four players, three shut in base camp; the Moth and the Tapper commit to the one miner
## out, and a third (stand-in) creature waits for a place until one stands down.

const C = preload("res://tests/scenario/director/crew_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())
	Tuning.set_dev_override("creatures.enabled", {"moth": 1, "tapper": 1, "stythe": 1})


func after_all() -> void:
	Tuning.clear_dev_overrides()


func test_one_out() -> void:
	var s: Scenario = make({"seed": 41, "fixture": C.hall()})
	var ids: Array[int] = C.crew(s, ["ann", "bob", "cid", "dot"] as Array[String])
	C.providers(s, {ids[1]: true, ids[2]: true, ids[3]: true}, {})
	s.place_stand_in(WorldIds.EntityKind.MOTH, Vector2i(2, 2))
	s.place_stand_in(WorldIds.EntityKind.TAPPER, Vector2i(4, 2))
	s.place_stand_in(WorldIds.EntityKind.STYTHE, Vector2i(6, 2))
	s.step(2)
	assert_eq(s.run.crew.count, 1, "one miner out")
	var gate: HuntGate = s.run.creatures.gate
	var moth: Creature = s.run.creatures.creature_of_kind(WorldIds.EntityKind.MOTH)
	var tapper: Creature = s.run.creatures.creature_of_kind(WorldIds.EntityKind.TAPPER)
	var third: Creature = s.run.creatures.creature_of_kind(WorldIds.EntityKind.STYTHE)
	assert_true(gate.request_commit(s.run, moth, ids[0], true))
	assert_true(gate.request_commit(s.run, tapper, ids[0], true))
	# Lambdas capture ints by value: count in arrays.
	var waited: Array[int] = [0]
	var placed_at: Array[int] = [-1]
	s.on_tick = func(sc: Scenario) -> void:
		if gate.is_hunting(third):
			return
		if gate.request_commit(sc.run, third, ids[0], true):
			placed_at[0] = sc.run.tick
		else:
			waited[0] += 1
		if sc.run.tick == 30:
			gate.stand_down(sc.run, moth, "lost them")
	s.step(40)
	gut.p("the third creature waited %d ticks, then committed at tick %d" % [waited[0], placed_at[0]])
	assert_gt(waited[0], 20)
	assert_eq(placed_at[0], 31, "the place it waited for, on the next attempt")
	assert_gt(s.run.crew.sealed_seconds(ids[1]), 1.0, "time in a sealed base camp is kept for telemetry")
