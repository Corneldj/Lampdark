extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-14: with NET-06 at 120 ms, a step out of reach issued before the end on the victim's screen
## makes the grab miss; a Caught victim is torn out of the man-trap with its wound; it never drags two.

const H = preload("res://tests/scenario/creatures/stythe_hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_step_before_the_end_at_120_ms() -> void:
	var s: Scenario = make({"seed": 1501, "fixture": H.road(), "overrides": H.W.ON})
	var h: H = H.new()
	h.build(s)
	h.ann.link(120, 0.0)
	assert_true(h.until_state(&"windup", 300))
	var w: CreatureWindUp = h.st.wind_up
	# Away from it, pressed 5 ticks before the end on her screen.
	var away: float = 180.0 if h.st.position(s.run).x > s.run.registry.get_entity(h.ann.entity_id).position.x else 0.0
	h.ann.at(w.end_tick - 5).move(away, InputRecord.Gait.RUN, 20)
	s.step(w.end_tick - s.run.tick + 6)
	assert_eq(w.outcome, CreatureWindUp.Outcome.MISSED, "she stepped out before the end")
	assert_ne(s.run.miner_state.life(h.ann.entity_id), MinerTransitions.Life.GRABBED)


func test_torn_out_of_a_man_trap() -> void:
	var s: Scenario = make({"seed": 1502, "fixture": H.road(), "overrides": H.W.ON})
	var h: H = H.new()
	h.build(s)
	var wounds: Array[int] = []
	s.run.holds.trap_wound = func(v: int) -> void: wounds.append(v)
	assert_true(s.run.holds.catch(s.run, h.ann.entity_id, CaughtHold.Kind.MAN_TRAP, 7))
	assert_true(h.until_state(&"drag", 300), "a Caught miner is taken")
	assert_eq(s.run.holds.caught_in(h.ann.entity_id), null, "torn out of the trap")
	assert_eq(wounds, [h.ann.entity_id] as Array[int], "with its wound")


func test_never_two_drags() -> void:
	var s: Scenario = make({"seed": 1503, "fixture": H.road(), "overrides": H.W.ON})
	var h: H = H.new()
	h.build(s)
	var bob: MinerHandle = H.W.miner(s, "bob", Vector2i(45, 2))
	assert_true(h.until_state(&"drag", 300))
	assert_false(h.st.hunt.grab(s.run, h.st, bob.entity_id, false), "one victim at a time")
	assert_eq(s.run.holds.grab_of(bob.entity_id), null)
