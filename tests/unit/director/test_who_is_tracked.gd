extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-01 (Gameplay §10.1): the Draught tracks every conscious miner, Upright, Caught or Grabbed,
## the operator included. Hired Hands, Bess, the unconscious and the dead hold no value, and a miner
## who comes round starts again at 0.

const D = preload("res://tests/scenario/director/draught_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_who_holds_an_intensity() -> void:
	var s: Scenario = make({"seed": 901, "fixture": D.hall(), "director": true})
	var ids: Array[int] = D.crew(s, ["ann", "ben", "cat", "dan"] as Array[String], ["a", "c", "d", "e"] as Array[String])
	var bess: SimEntity = s.run.registry.create(WorldIds.EntityKind.BESS, Vector2(41.5, 1.5))
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == ids[3]
	D.stand_in(s)
	s.step(2)
	for i: int in 3:
		D.set_value(s, ids[i], 50.0)
	assert_eq(D.value(s, ids[3]), -1.0, "a Hired Hand holds none")
	assert_false(s.run.draught.records.has(bess.id), "Bess holds none")
	# Caught and Grabbed are conscious: still tracked.
	assert_true(s.run.holds.catch(s.run, ids[0], CaughtHold.Kind.MAN_TRAP, 1))
	assert_gt(s.run.holds.grab(s.run, ids[1], GrabHold.Kind.TAPPER_PIN, 0, 1000), 0)
	s.step(2)
	assert_gt(D.value(s, ids[0]), 50.0, "Caught: still tracked")
	assert_gt(D.value(s, ids[1]), 50.0, "Grabbed: still tracked")
	# Cat falls unconscious; Ann is shot dead.
	s.run.miner_state.fall_unconscious(ids[2], "test")
	s.run.miner_state.kill(ids[0], "test")
	s.step(2)
	assert_eq(D.value(s, ids[2]), -1.0, "the unconscious hold none")
	assert_eq(D.value(s, ids[0]), -1.0, "the dead hold none")
	# Cat comes round: from 0.
	s.run.miner_state.revive(ids[2], &"kit")
	s.step(2)
	assert_eq(D.value(s, ids[2]), 0.0, "a miner who comes round starts again at 0")
