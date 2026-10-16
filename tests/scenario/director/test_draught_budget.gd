extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-01's cost (Proposed): at most 0.1 ms a tick with five miners. The real light, lamps and paths
## (no stand-ins): five miners in an unlit hall, some in company, two alone gathering their dark, a
## lamp over one stretch. A wall-clock test: the round runs it alone (SOLO), and with
## LB_TIMING_REPORT_ONLY set (shared CI runners, Wine) the times are printed, not asserted. The
## median is held to the budget; the 99th percentile is reported (a debug build's tail).

const D = preload("res://tests/scenario/director/draught_world.gd")
const W = preload("res://tests/scenario/net/net04_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_five_miners_cost_at_most_0_1_ms_a_tick() -> void:
	var s: Scenario = make({"seed": 804, "fixture": D.hall(), "director": true})
	D.crew(s, ["a1", "a2", "a3", "a4", "a5"] as Array[String], ["a", "b", "c", "d", "e"] as Array[String])
	W.lamp(s, Vector2(31.5, 1.5), 4.0)
	s.step(1000)
	var key: String = TickTimer.system_key(s.run.draught)
	var p50: int = s.run.timer.percentile(key, 50.0)
	var p99: int = s.run.timer.percentile(key, 99.0)
	gut.p("the Draught: p50 %d us, p99 %d us a tick with five miners" % [p50, p99])
	if OS.get_environment("LB_TIMING_REPORT_ONLY").is_empty():
		assert_lt(p50, 100, "within 0.1 ms")
