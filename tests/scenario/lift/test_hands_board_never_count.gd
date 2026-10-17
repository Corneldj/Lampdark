extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-10 (Gameplay §3.6, §13.9): Hired Hands board with their human and ride, but never pull and
## never count toward the majority: a Hand's pull is refused, and Ann alone with two Hands aboard is
## the whole majority of one.

const K = preload("res://tests/unit/lift/cage_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_hands_ride_but_never_count() -> void:
	var s: Scenario = make({"seed": 10801, "fixture": K.E.T.C.scenario_fixture()})
	K.ready(s)
	var cage: Cage = s.run.cage
	var ann: MinerHandle = K.aboard(s, "ann", 0)
	var hal: MinerHandle = K.aboard(s, "hal", 1)
	var hob: MinerHandle = K.aboard(s, "hob", 2)
	var hands: Array[int] = [hal.entity_id, hob.entity_id]
	s.run.crew.is_hand_driven = func(e: int) -> bool: return hands.has(e)
	assert_eq(SignalCord.electorate(s.run, cage.deck), 1, "only Ann counts")
	K.pull(s, hal)
	assert_eq(str(cage.refused.back()["why"]), "a Hand")
	assert_true(cage.cord.votes.is_empty(), "a Hand's pull is no vote")
	K.pull(s, ann)
	assert_eq(cage.state, Cage.State.BELL, "Ann alone: one of one")
	assert_true(s.run_until(func(_sc: Scenario) -> bool: return cage.is_departed(), K.bell_ticks() + 10))
	for h: int in hands:
		assert_true(cage.riders().has(h), "the Hands board with her and ride")
