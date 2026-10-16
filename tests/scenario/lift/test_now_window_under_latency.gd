extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-04 with NET-06 (GDD §15.2): 'Now!' is judged against the cue as it reached the presser. Over
## emulated links of 40, 120 and 250 ms round trips with 2% loss, a press 0.9 s after the cue showed
## on the presser's screen succeeds and one 1.1 s after misses; over a 250 ms one-way link it
## succeeds although the server receives it about 1.4 s after its own cue.

const J = preload("res://tests/unit/lift/job_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


## [outcomes, ticks from the cue to the server taking the press].
func _run(seed_value: int, rtt_ms: int, loss_pct: float, seconds: float) -> Array:
	var s: Scenario = make({"seed": seed_value, "fixture": J.room()})
	var events: Array = []
	J.cue_press(s, events)
	var ann: MinerHandle = J.beside(s, "ann", J.H_TILE, Vector2i(1, 0))
	var bob: MinerHandle = J.beside(s, "bob", J.P_TILE, Vector2i(-1, 0))
	for h: MinerHandle in [ann, bob]:
		h.link(rtt_ms, loss_pct)
	s.step(40)
	J.hold(s, ann, 400)
	assert_true(J.press_after_cue(s, bob, seconds, 80), "the cue showed on Bob's screen")
	var cue: int = -1
	var press: int = -1
	for e: Dictionary in s.run.two_miner.log:
		if str(e["what"]) == "cue" and cue < 0:
			cue = int(Variants.number(e["tick"]))
		if str(e["what"]) == "press" and press < 0:
			press = int(Variants.number(e["tick"]))
	return [J.whats(events), press - cue]


func test_the_window_is_the_presser_s_own() -> void:
	var seed_value: int = 2301
	for rtt: int in [40, 120, 250]:
		for case: Array in [[0.9, "success"], [1.1, "miss:late"]]:
			var after_s: float = float(Variants.number(case[0]))
			seed_value += 1
			var r: Array = _run(seed_value, rtt, 2.0, after_s)
			var got: Array[String] = r[0]
			gut.p("%d ms RTT, 2%% loss: pressed %.1f s after the cue on screen: %s (the server took it %d ticks after its cue)" % [
				rtt, after_s, got, r[1]])
			assert_eq(got, ["cue", str(case[1])] as Array[String], "%d ms, %.1f s" % [rtt, after_s])


func test_over_a_250_ms_one_way_link_a_fair_press_counts() -> void:
	var r: Array = _run(2310, 500, 0.0, 0.9)
	var got: Array[String] = r[0]
	var took_s: float = int(Variants.number(r[1])) / Tuning.f(&"net.tick_hz")
	gut.p("250 ms each way: the server took the press %.2f s after its own cue: %s" % [took_s, got])
	assert_eq(got, ["cue", "success"] as Array[String], "0.9 s on the presser's screen counts")
	assert_gt(took_s, 1.25, "although the server had it well after 1 s of its own")
