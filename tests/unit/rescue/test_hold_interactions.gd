extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-03's interactions: a drag tears a caught miner out (TORN_OUT; a man-trap's wound rule
## runs); a pin holds a caught miner in place, and once broken leaves them Caught.

const H = preload("res://tests/scenario/rescue/hold_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_drag_tears_out_of_a_man_trap() -> void:
	var s: Scenario = make({"seed": 6, "fixture": H.hall()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.step(1)
	var wounded: Array[int] = []
	s.run.holds.trap_wound = func(victim: int) -> void: wounded.append(victim)
	s.run.holds.catch(s.run, ann.entity_id, CaughtHold.Kind.MAN_TRAP, 3)
	s.step(1)
	var ended: Array[int] = []
	s.run.holds.caught_ended.connect(func(_t: int, outcome: CaughtHold.Outcome, _v: int) -> void: ended.append(outcome))
	assert_gt(s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.STYTHE_DRAG, 98, 400), 0)
	s.step(1)
	assert_eq(ended, [CaughtHold.Outcome.TORN_OUT] as Array[int], "torn out")
	assert_eq(wounded, [ann.entity_id] as Array[int], "the man-trap's wound rule ran")
	assert_eq(H.life(s, ann.entity_id), MinerTransitions.Life.GRABBED)
	assert_null(s.run.holds.caught_in(ann.entity_id))


func test_broken_pin_leaves_them_caught() -> void:
	var s: Scenario = make({"seed": 7, "fixture": H.hall()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.step(1)
	s.run.holds.catch(s.run, ann.entity_id, CaughtHold.Kind.TIMBER_PIN, 4)
	s.step(1)
	var id: int = s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.TAPPER_PIN, 99, 500)
	s.step(1)
	assert_eq(H.life(s, ann.entity_id), MinerTransitions.Life.GRABBED)
	assert_true(s.run.holds.end_grab(s.run, id, GrabHold.Outcome.BROKEN))
	s.step(1)
	assert_eq(H.life(s, ann.entity_id), MinerTransitions.Life.CAUGHT, "the pin broken: still in the trap")
	assert_not_null(s.run.holds.caught_in(ann.entity_id))
