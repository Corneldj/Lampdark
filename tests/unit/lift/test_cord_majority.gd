extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-10 (Gameplay §3.6, §13.9): the signal cord's majority. Before the engine's 60 s run-up a pull
## does nothing and is not stored. With four conscious in a friends' run, three aboard pulling ring
## the bell and two do not. Hired Hands never pull or count, and the unconscious and the dead never
## count; a vote stands only while its miner stays aboard and conscious.

const K = preload("res://tests/unit/lift/cage_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _make(run_seed: int) -> Scenario:
	return make({"seed": run_seed, "fixture": K.E.T.C.scenario_fixture()})


func test_before_the_run_up_a_pull_does_nothing() -> void:
	var s: Scenario = _make(10001)
	K.ready(s, 30.0)
	var ann: MinerHandle = K.aboard(s, "ann")
	var cage: Cage = s.run.cage
	K.pull(s, ann)
	assert_eq(str(cage.refused.back()["why"]), "run-up")
	assert_true(cage.cord.votes.is_empty(), "not stored")
	assert_true(s.run_until(func(sc: Scenario) -> bool: return sc.run.engine.run_up_complete(sc.run), 800))
	s.step(10)
	assert_eq(cage.state, Cage.State.WAITING, "no bell from a pull made before the run-up")
	assert_eq(K.bells(s).size(), 0)
	K.pull(s, ann)
	assert_eq(cage.state, Cage.State.BELL, "pulled again after it: alone in the run, the majority")


func test_four_conscious_need_three_aboard_pulling() -> void:
	var s: Scenario = _make(10002)
	K.ready(s)
	var cage: Cage = s.run.cage
	var ann: MinerHandle = K.aboard(s, "ann", 0)
	var bob: MinerHandle = K.aboard(s, "bob", 1)
	var cid: MinerHandle = K.aboard(s, "cid", 2)
	K.at_home(s, "dot")
	assert_eq(SignalCord.required(s.run, cage.deck), 3, "four conscious: three")
	K.pull(s, ann)
	K.pull(s, bob)
	s.step(10)
	assert_eq(cage.state, Cage.State.WAITING, "two do not ring it")
	assert_eq(cage.cord.pullers().size(), 2)
	K.pull(s, cid)
	assert_eq(cage.state, Cage.State.BELL, "three do")


func test_hands_the_unconscious_and_the_dead_never_count() -> void:
	var s: Scenario = _make(10003)
	K.ready(s)
	var cage: Cage = s.run.cage
	var ann: MinerHandle = K.aboard(s, "ann", 0)
	var hand: MinerHandle = K.aboard(s, "hand", 1)
	var bob: MinerHandle = K.aboard(s, "bob", 2)
	var cid: MinerHandle = K.at_home(s, "cid")
	var dot: MinerHandle = K.at_home(s, "dot")
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == hand.entity_id
	s.run.miner_state.fall_unconscious(cid.entity_id, "test")
	s.run.miner_state.kill(dot.entity_id, "test")
	s.step(3)
	assert_eq(SignalCord.electorate(s.run, cage.deck), 2, "Ann and Bob: no Hand, nobody down")
	K.pull(s, hand)
	assert_eq(str(cage.refused.back()["why"]), "a Hand", "a Hand's pull is refused")
	K.pull(s, ann)
	assert_eq(cage.state, Cage.State.WAITING, "one of two is no majority")
	# A vote stands while its miner stays aboard and conscious.
	K.move_to(s, ann, cage.deck.position - Vector2i(2, 2))
	assert_true(cage.cord.votes.is_empty(), "off the deck: her vote is gone")
	K.move_to(s, ann, K.cord_tiles(s)[0])
	K.pull(s, ann)
	K.pull(s, bob)
	assert_eq(cage.state, Cage.State.BELL, "two of two")
