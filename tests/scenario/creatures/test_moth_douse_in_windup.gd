extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-04 with NET-06: shuttering (0.2 s) inside the 1.0 s wind-up makes the smother miss, at 0
## and at 120 ms round trip; left open, it lands.

const A = preload("res://tests/scenario/creatures/moth_awake_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


## Returns [wind-up outcome, ann's life].
func _run(run_seed: int, rtt_ms: int, douse: bool) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": A.road(40)})
	var m: Moth = A.awake(s, Vector2i(10, 2), true)
	var ann: MinerHandle = A.lit_miner(s, "ann", Vector2i(20, 2))
	if rtt_ms > 0:
		ann.link(rtt_ms, 0.0)
	assert_gte(A.until_state(s, m, &"windup", 400), 0, "the wind-up begins")
	if douse:
		ann.at(s.run.tick).lamp(true, 1)
	s.step(40)
	var w: Array[Dictionary] = s.run.creatures.log.of_type(&"wind_up")
	assert_eq(w.size(), 1, "one wind-up, finished once")
	return [str(w[0]["outcome"]), A.life(s, ann.entity_id)]


func test_douse_at_0_and_120_ms() -> void:
	for rtt: int in [0, 120]:
		var r: Array = _run(50 + rtt, rtt, true)
		assert_eq(str(r[0]), "missed", "doused inside the wind-up at %d ms: it misses" % rtt)
		assert_eq(int(Variants.number(r[1])), MinerTransitions.Life.UPRIGHT)
		var open: Array = _run(60 + rtt, rtt, false)
		assert_eq(str(open[0]), "landed", "left open at %d ms: it lands" % rtt)
		assert_eq(int(Variants.number(open[1])), MinerTransitions.Life.UNCONSCIOUS)
