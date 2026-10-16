extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-08 (Gameplay §3.9, 1:40:00): a late throttle backfires (one 30 np bang) and the engine stays
## primed; the crank let go and taken again, with no new prime, catches on time.

const E = preload("res://tests/unit/lift/engine_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_late_throttle_backfires_and_the_second_crank_catches() -> void:
	var s: Scenario = make({"seed": 7301, "fixture": E.T.C.scenario_fixture()})
	E.ready(s)
	var ann: MinerHandle = E.at(s, "ann", "engine_prime")
	var engine: WinderEngine = s.run.engine
	E.prime(s, ann)
	E.move_to(s, ann, "engine_crank")
	var bob: MinerHandle = E.at(s, "bob", "engine_throttle")
	var from: int = s.run.noise.event_log.size()
	E.hold(s, ann, 160)
	assert_true(E.throttle_after_cue(s, bob, 1.5), "Bob throttles 1.5 s after the clank")
	var bangs: Array[NoiseSystem.Event] = E.events(s, NoiseTypes.Type.BACKFIRE, from)
	assert_eq(bangs.size(), 1, "one backfire")
	assert_eq(bangs[0].level_np, 30.0)
	assert_eq(engine.state, WinderEngine.State.PRIMED, "the prime kept")
	assert_false(s.run.repair.is_done(&"start"))
	s.step(140)
	# Let go and taken again: no prime this time.
	var primes: int = engine.log.filter(func(e: Dictionary) -> bool: return str(e["what"]) == "prime").size()
	E.hold(s, ann, 200)
	assert_true(E.throttle_after_cue(s, bob, 0.4))
	assert_eq(engine.state, WinderEngine.State.RUNNING, "the second crank catches")
	assert_eq(engine.log.filter(func(e: Dictionary) -> bool: return str(e["what"]) == "prime").size(), primes, "with no new prime")
	assert_true(s.run.repair.is_done(&"start"))
