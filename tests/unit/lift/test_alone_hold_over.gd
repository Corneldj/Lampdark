extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-04 (Gameplay §3.3, §11.11): alone, a 'Now!' place holds 3 s after its miner lets go, so one
## miner holds the trip, lets go, turns and throws the switch: pressed 2.9 s after letting go it
## succeeds, at 3.1 s it misses. Both measured on the miner's own screen. A lone human with Hands has
## the alone rules too, and a second conscious human ends them.

const J = preload("res://tests/unit/lift/job_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


## One miner between H (west) and P (east): holds H, lets go, turns east and presses P `seconds`
## after letting go (the server compares the stamps of the inputs that let go and pressed).
func _alone_press(seed_value: int, seconds: float, events: Array) -> Dictionary:
	var s: Scenario = make({"seed": seed_value, "fixture": J.room()})
	J.cue_press(s, events, 0.0, J.LONE_H, J.LONE_P)
	var ann: MinerHandle = J.lone(s, "ann")
	s.step(10)
	assert_true(AloneRules.is_alone(s.run, ann.entity_id), "a friends lobby of one is solo")
	J.hold(s, ann, 30)
	var let_go: int = s.run.tick + 30
	var turn: int = let_go + 5
	var at: int = let_go + roundi(seconds * Tuning.f(&"net.tick_hz"))
	ann.at(turn).face(0.0)
	ann.at(at).hold(InputRecord.HOLD_INTERACT, 2)
	s.step(at - s.run.tick + 30)
	return {"s": s}


func test_alone_the_trip_holds_three_seconds() -> void:
	var ok: Array = []
	_alone_press(2101, 2.9, ok)
	assert_eq(J.whats(ok), ["cue", "success"] as Array[String], "2.9 s after letting go: thrown")
	var late: Array = []
	_alone_press(2102, 3.1, late)
	assert_eq(J.whats(late), ["cue", "miss:let go"] as Array[String], "3.1 s: too late, the trip had gone")


func test_in_a_crew_letting_go_ends_it_at_once() -> void:
	var s: Scenario = make({"seed": 2103, "fixture": J.room()})
	var events: Array = []
	J.cue_press(s, events)
	var ann: MinerHandle = J.beside(s, "ann", J.H_TILE, Vector2i(1, 0))
	var bob: MinerHandle = J.beside(s, "bob", J.P_TILE, Vector2i(-1, 0))
	s.step(10)
	J.hold(s, ann, 6)
	s.step(16)
	J.hold(s, bob, 2)
	s.step(20)
	assert_eq(J.whats(events), ["cue", "miss:let go"] as Array[String], "Ann let go before Bob threw it")


func test_a_lone_human_with_hands_is_alone_until_a_second_human_comes_round() -> void:
	# A friends crew that began with two, one of them down: the other is a lone human.
	var s: Scenario = make({"seed": 2104, "fixture": J.room()})
	var events: Array = []
	var job: CuePress = J.cue_press(s, events, 0.0, J.LONE_H, J.LONE_P)
	var ann: MinerHandle = J.lone(s, "ann")
	var bob: MinerHandle = s.add_miner("bob", Vector2i(12, 2))
	var hand: MinerHandle = s.add_miner("hand", Vector2i(13, 2))
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == hand.entity_id
	s.step(5)
	assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.ROOF_FALL))
	s.step(5)
	assert_true(AloneRules.is_alone(s.run, ann.entity_id), "Ann, with only a Hand standing, is alone")
	assert_true(s.run.lone.active_substitutions(s.run, ann.entity_id).has("solo_jobs"), "RSC-09's solo jobs on")
	J.hold(s, ann, 10)
	s.step(12)
	assert_true(job.alone, "the cue came under the alone rules")
	s.run.miner_state.revive(bob.entity_id, &"test")
	s.step(5)
	assert_false(AloneRules.is_alone(s.run, ann.entity_id), "Bob came round: normal rules")
	assert_false(s.run.lone.active_substitutions(s.run, ann.entity_id).has("solo_jobs"))
