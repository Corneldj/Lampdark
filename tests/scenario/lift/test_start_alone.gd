extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-08 with LFT-04's hold-over: alone, one miner starts the engine. She primes, holds the crank to
## its top, lets go (the crank holds at the top for 3 s), crosses to the throttle and throttles: it
## catches.

const E = preload("res://tests/unit/lift/engine_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_one_miner_starts_it_through_the_hold_over() -> void:
	var s: Scenario = make({"seed": 7601, "fixture": E.T.C.scenario_fixture()})
	E.ready(s)
	var ann: MinerHandle = E.at(s, "ann", "engine_prime")
	var engine: WinderEngine = s.run.engine
	assert_true(AloneRules.is_alone(s.run, ann.entity_id), "a crew of one")
	E.prime(s, ann)
	E.move_to(s, ann, "engine_crank")
	E.hold(s, ann, 86)
	assert_true(s.run_until(func(_sc: Scenario) -> bool: return engine.crank != null and engine.crank.state == CuePress.State.READY, 120),
		"the crank at its top")
	s.step(8)
	# Let go, across to the throttle, and throttle within the hold-over.
	E.move_to(s, ann, "engine_throttle")
	E.hold(s, ann, 2)
	s.step(20)
	assert_true(engine.is_running(), "it caught")
	assert_true(s.run.repair.is_done(&"start"))
