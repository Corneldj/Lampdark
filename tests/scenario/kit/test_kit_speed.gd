extends "res://tests/scenario/kit/scenario_test.gd"
## FND-09's speed target (Proposed): 1,000 ticks of a four-miner scenario in under 2 s on a CI
## core. GEN-03's grey box does not exist yet, so this runs on the two-cell test map with the
## light passes on. The guard here is loose (4 s) so a slow runner does not flake; the measured
## time is printed for the record. With LB_TIMING_REPORT_ONLY set (shared CI runners, Wine), it is
## only reported.

func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_thousand_ticks_of_four_miners() -> void:
	var s: Scenario = make({"seed": 1000, "fixture": "test"})
	var tiles: Array[Vector2i] = [Vector2i(2, 1), Vector2i(5, 13), Vector2i(12, 14), Vector2i(10, 8)]
	for i: int in 4:
		var h: MinerHandle = s.add_miner("m%d" % i, tiles[i])
		for leg: int in 20:
			h.at(leg * 50).move(float((i * 90 + leg * 37) % 360), InputRecord.Gait.WALK, 40) \
				.hold(InputRecord.HOLD_CHECK_LAMP, 5).press(ActionRecord.Kind.CALLOUT, leg)
	var started: int = Time.get_ticks_usec()
	s.step(1000)
	var seconds: float = (Time.get_ticks_usec() - started) / 1000000.0
	gut.p("1,000 ticks of four miners: %.2f s (target 2 s)" % seconds)
	assert_eq(s.run.tick, 1000)
	for h: MinerHandle in s.miners:
		assert_eq(h.inputs_sent, 1000)
	if OS.get_environment("LB_TIMING_REPORT_ONLY").is_empty():
		assert_lt(seconds, 4.0, "well inside the loose guard")
