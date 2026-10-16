extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-03's queries for creatures (Gameplay §10.5): attendable (30), marked (50), anywhere (80), the
## highest at or above a threshold (ties to the one above it longer, then the lowest id), and
## alone_since. Creatures read it through the hunt gate's pull_of. The unconscious and the dead have
## no Pull, and a revived miner starts again at 0.

const D = preload("res://tests/scenario/director/draught_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_thresholds_and_the_highest() -> void:
	var s: Scenario = make({"seed": 2401, "fixture": D.hall(), "director": true})
	var ids: Array[int] = D.crew(s, ["ann", "ben", "cat"] as Array[String], ["a", "c", "e"] as Array[String])
	D.stand_in(s)
	s.run.pull.ring_of = func(_m: int) -> int: return 0
	s.step(2)
	var pull: Pull = s.run.pull
	pull.set_value(ids[0], 31.0)
	pull.set_value(ids[1], 55.0)
	pull.set_value(ids[2], 85.0)
	s.step(1)
	assert_true(pull.at_least(ids[0], 30.0) and not pull.at_least(ids[0], 50.0))
	assert_eq(pull.marked_miners(), [ids[1], ids[2]] as Array[int], "marked at 50")
	assert_eq(pull.highest_at_or_above(80.0), ids[2])
	assert_eq(pull.highest_at_or_above(90.0), 0, "nobody that high")
	assert_almost_eq(float(Variants.number(s.run.creatures.gate.pull_of.call(ids[1]))), 55.0, 0.01, "creatures read it through the gate")
	# A tie at 60: the one above 50 longer wins (Ben crossed 50 first).
	pull.set_value(ids[2], 40.0)
	s.step(1)
	pull.set_value(ids[2], 60.0)
	pull.set_value(ids[1], 60.0)
	s.step(1)
	pull.set_value(ids[2], 60.0)
	pull.set_value(ids[1], 60.0)
	assert_eq(pull.highest_at_or_above(50.0), ids[1], "a tie goes to the one marked longer")


func test_alone_since_and_who_holds_one() -> void:
	var s: Scenario = make({"seed": 2402, "fixture": D.hall(), "director": true})
	var ids: Array[int] = D.crew(s, ["ann", "ben"] as Array[String], ["a", "b"] as Array[String])
	D.stand_in(s)
	s.step(10)
	var together: int = s.run.pull.alone_since(ids[0])
	assert_gt(together, 0, "in a pair: alone_since keeps up")
	s.run.movement.place(s.run, ids[1], Vector2(30.5, 1.5))
	s.step(20)
	var since: int = s.run.pull.alone_since(ids[0])
	s.step(20)
	assert_eq(s.run.pull.alone_since(ids[0]), since, "alone: the tick they were last in company")
	# The unconscious and the dead hold none; a revived miner starts at 0.
	s.run.pull.set_value(ids[1], 40.0)
	s.run.miner_state.fall_unconscious(ids[1], "test")
	s.step(2)
	assert_false(s.run.pull.records.has(ids[1]), "the unconscious hold no Pull")
	s.run.miner_state.revive(ids[1], &"kit")
	s.step(2)
	assert_almost_eq(s.run.pull.value_of(ids[1]), 0.0, 0.01, "revived: from 0")
	s.run.miner_state.kill(ids[0], "test")
	s.step(2)
	assert_false(s.run.pull.records.has(ids[0]), "the dead hold none")
