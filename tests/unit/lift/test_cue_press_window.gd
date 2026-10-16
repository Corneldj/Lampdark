extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-04: a cue and a press (Gameplay §3.3, §3.6; GDD §15.2). At 0 ms latency a press 0.95 s after
## the cue on the presser's screen succeeds and one at 1.05 s misses; a press before the cue misses;
## a press with nobody at the holder's place times nothing; after a success or a miss the holder
## must let go and take the place again for a new cue.

const J = preload("res://tests/unit/lift/job_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _crew(seed_value: int, events: Array, hold_to_ready_s: float = 0.0) -> Array:
	var s: Scenario = make({"seed": seed_value, "fixture": J.room()})
	var job: CuePress = J.cue_press(s, events, hold_to_ready_s)
	var ann: MinerHandle = J.beside(s, "ann", J.H_TILE, Vector2i(1, 0))
	var bob: MinerHandle = J.beside(s, "bob", J.P_TILE, Vector2i(-1, 0))
	s.step(10)
	return [s, job, ann, bob]


func test_a_press_inside_the_window_succeeds_and_outside_misses() -> void:
	for case: Array in [[0.95, "success"], [1.05, "miss:late"]]:
		var after_s: float = float(Variants.number(case[0]))
		var outcome: String = str(case[1])
		var events: Array = []
		var c: Array = _crew(1901 if outcome == "success" else 1902, events)
		var s: Scenario = c[0]
		var ann: MinerHandle = c[2]
		var bob: MinerHandle = c[3]
		J.hold(s, ann, 200)
		assert_true(J.press_after_cue(s, bob, after_s), "the cue showed on Bob's screen")
		assert_eq(J.whats(events), ["cue", outcome] as Array[String], "a press %.2f s after the cue" % after_s)
		var job: CuePress = c[1]
		assert_eq(job.state, CuePress.State.SPENT, "spent until the trip is taken again")


func test_a_press_before_the_cue_misses() -> void:
	# The crank's stroke: the cue comes after 2 s of holding; Bob opens the throttle at 1 s.
	var events: Array = []
	var c: Array = _crew(1903, events, 2.0)
	var s: Scenario = c[0]
	var ann: MinerHandle = c[2]
	var bob: MinerHandle = c[3]
	J.hold(s, ann, 200)
	s.step(20)
	J.hold(s, bob, 2)
	s.step(10)
	assert_eq(J.whats(events), ["miss:early"] as Array[String], "before the cue: a miss, no cue yet")
	# The same cue, before it reaches the presser's screen at all (pressed the tick the trip is held).
	var events2: Array = []
	var d: Array = _crew(1904, events2)
	var s2: Scenario = d[0]
	var ann2: MinerHandle = d[2]
	var bob2: MinerHandle = d[3]
	J.hold(s2, ann2, 200)
	J.hold(s2, bob2, 2)
	s2.step(10)
	assert_eq(J.whats(events2), ["cue", "miss:early"] as Array[String], "pressed as the trip was taken")


func test_nothing_to_time_with_nobody_at_the_holders_place() -> void:
	var events: Array = []
	var c: Array = _crew(1905, events)
	var s: Scenario = c[0]
	var bob: MinerHandle = c[3]
	J.hold(s, bob, 2)
	s.step(20)
	assert_eq(events.size(), 0, "a press with no trip held does nothing")


func test_a_new_cue_needs_the_place_taken_again() -> void:
	var events: Array = []
	var c: Array = _crew(1906, events)
	var s: Scenario = c[0]
	var ann: MinerHandle = c[2]
	var bob: MinerHandle = c[3]
	J.hold(s, ann, 400)
	J.press_after_cue(s, bob, 1.5, 60)
	assert_eq(J.whats(events), ["cue", "miss:late"] as Array[String])
	s.step(60)
	assert_eq(events.size(), 2, "held on, no second cue")
	s.step(400)
	J.hold(s, ann, 200)
	assert_true(J.press_after_cue(s, bob, 0.5))
	assert_eq(J.whats(events), ["cue", "miss:late", "cue", "success"] as Array[String], "taken again: a new cue")
	assert_true(s.run.two_miner.log.size() >= 6, "cues, presses and outcomes logged for NET-07")


## Never sent: the window, the hold-over or a ruling. The presser's client hears the cue as a sound
## and gets nothing else of the job; the job's own outcome events are LFT-05's and LFT-08's.
func test_nothing_of_the_timing_reaches_a_client() -> void:
	var events: Array = []
	var c: Array = _crew(1907, events)
	var s: Scenario = c[0]
	var ann: MinerHandle = c[2]
	var bob: MinerHandle = c[3]
	J.hold(s, ann, 200)
	J.press_after_cue(s, bob, 1.5, 60)
	assert_eq(J.whats(events), ["cue", "miss:late"] as Array[String])
	for h: MinerHandle in [ann, bob]:
		for m: Dictionary in h.capture.messages:
			var type: int = int(Variants.number(m["type"]))
			assert_true(type in [Protocol.Msg.FRAME, Protocol.Msg.STATUS, Protocol.Msg.INVENTORY, Protocol.Msg.PONG,
				Protocol.Msg.WELCOME, Protocol.Msg.SHEET, Protocol.Msg.CLOSE_UP, Protocol.Msg.AMBIENT],
				"%s got a %s" % [h.name, Protocol.Msg.find_key(type)])
