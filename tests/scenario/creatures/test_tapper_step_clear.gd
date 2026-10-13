extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-09: the wind-up lasts 10 ticks; a miner who steps beyond 1.5 tiles before its end is missed
## (at 0 and at 120 ms round trip, under NET-06's defender rule) and the Tapper listens again.

const W = preload("res://tests/scenario/creatures/hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	W.ring(1)


func after_each() -> void:
	super.after_each()
	Tuning.clear_dev_overrides()


func _step_clear(rtt: int) -> Dictionary:
	var s: Scenario = make({"seed": 60 + rtt, "fixture": W.road()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(10, 5))
	ann.link(rtt, 0.0)
	var t: Tapper = W.tapper(s, Vector2i(10, 4))
	t.follower.stop()
	s.step(4)
	W.talk(s, ann)
	W.until_state(s, t, &"windup", 20)
	# She runs east the moment the arm leaves the wall.
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.RUN, 30)
	s.step(30)
	var w: Array[Dictionary] = s.run.creatures.log.of_type(&"wind_up")
	return {"outcome": str(w[0]["outcome"]) if not w.is_empty() else "none", "len": int(Variants.number(w[0]["end"])) - int(Variants.number(w[0]["start"])) if not w.is_empty() else -1,
		"state": t.state.name, "life": W.life(s, ann.entity_id)}


func test_at_0_ms() -> void:
	var r: Dictionary = _step_clear(0)
	gut.p("0 ms: %s" % r)
	var length: int = r["len"]
	var outcome: String = r["outcome"]
	var life: int = r["life"]
	assert_eq(length, 10, "10 ticks")
	assert_eq(outcome, "missed", "she stepped clear")
	assert_eq(life, MinerTransitions.Life.UPRIGHT)


func test_at_120_ms() -> void:
	var r: Dictionary = _step_clear(120)
	gut.p("120 ms: %s" % r)
	var outcome: String = r["outcome"]
	var life: int = r["life"]
	assert_eq(outcome, "missed", "the step, issued before the end on her screen, counts")
	assert_eq(life, MinerTransitions.Life.UPRIGHT)
