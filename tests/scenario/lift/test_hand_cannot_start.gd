extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-08 (Gameplay §13.9, §13.10): a Hired Hand never primes, cranks or throttles. Its prime is
## refused; primed by a player, its hold on the crank is refused, and so is its throttle.

const E = preload("res://tests/unit/lift/engine_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_hand_never_starts_the_engine() -> void:
	var s: Scenario = make({"seed": 7701, "fixture": E.T.C.scenario_fixture()})
	E.ready(s)
	var hand: MinerHandle = E.at(s, "hand", "engine_prime")
	var ann: MinerHandle = E.at(s, "ann", "engine_throttle")
	var engine: WinderEngine = s.run.engine
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == hand.entity_id
	E.prime(s, hand)
	assert_eq(str(engine.refused.back()["why"]), "a Hand", "no prime")
	assert_eq(engine.state, WinderEngine.State.COLD)
	# A player primes; the Hand takes neither the crank nor the throttle.
	E.move_to(s, hand, "engine_crank")
	E.move_to(s, ann, "engine_prime")
	E.prime(s, ann)
	assert_eq(engine.state, WinderEngine.State.PRIMED)
	E.face(s, hand, "engine_crank")
	E.hold(s, hand, 100)
	s.step(104)
	assert_eq(engine.crank.holder_place.holder, 0, "the crank refused to a Hand")
	assert_true(s.run.two_miner.refused.any(func(r: Dictionary) -> bool: return str(r.get("why", "")) == "a hand"))
	E.move_to(s, ann, "engine_crank")
	E.move_to(s, hand, "engine_throttle")
	E.hold(s, ann, 200)
	assert_false(E.throttle_after_cue(s, hand, 0.4) and engine.is_running(), "the Hand's throttle never catches")
	assert_false(engine.is_running())
