extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-03's grabs: grab_timed_out exactly at the limit; a drag then goes on as a body with no
## timer; a Grabbed miner cannot be grabbed again, a Caught or unconscious one can; every end has
## one of the listed outcomes.

const H = preload("res://tests/scenario/rescue/hold_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_timed_out_exactly_at_the_limit() -> void:
	var s: Scenario = make({"seed": 1, "fixture": H.hall()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.step(1)
	var id: int = s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.TAPPER_PIN, 99, 500)
	assert_gt(id, 0)
	assert_eq(H.ticks_to_timeout(s, id, 600), 500, "exactly at 500 ticks")
	s.step(1)
	assert_eq(H.life(s, ann.entity_id), MinerTransitions.Life.GRABBED, "the creature ends it (CRT-09 calls TIMED_OUT)")
	assert_true(s.run.holds.end_grab(s.run, id, GrabHold.Outcome.TIMED_OUT))
	s.step(1)
	assert_eq(H.life(s, ann.entity_id), MinerTransitions.Life.UNCONSCIOUS, "a pin run out: unconscious at the wall")


func test_drag_becomes_a_body() -> void:
	var s: Scenario = make({"seed": 2, "fixture": H.hall()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.step(1)
	var id: int = s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.STYTHE_DRAG, 99, 400)
	assert_eq(H.ticks_to_timeout(s, id, 500), 400)
	s.step(2)
	var g: GrabHold = s.run.holds.grabs[id]
	assert_eq(g.state, GrabHold.State.BODY, "past the conscious limit: a body")
	assert_eq(H.life(s, ann.entity_id), MinerTransitions.Life.UNCONSCIOUS)
	var before: int = g.elapsed
	s.step(200)
	assert_eq(g.elapsed, before, "no further timer")
	assert_true(s.run.holds.is_held(ann.entity_id))


func test_who_can_be_grabbed() -> void:
	var s: Scenario = make({"seed": 3, "fixture": H.hall()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var bob: MinerHandle = s.add_miner("bob", s.fixture.spot("b"))
	var cid: MinerHandle = s.add_miner("cid", s.fixture.spot("c"))
	s.step(1)
	assert_gt(s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.TAPPER_PIN, 99, 500), 0)
	s.step(1)
	assert_eq(s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.STYTHE_DRAG, 98, 400), -1, "a Grabbed miner cannot be grabbed again")
	s.run.holds.catch(s.run, bob.entity_id, CaughtHold.Kind.TIMBER_PIN, 5)
	s.step(1)
	assert_gt(s.run.holds.grab(s.run, bob.entity_id, GrabHold.Kind.TAPPER_PIN, 99, 500), 0, "a Caught one can")
	s.run.miner_state.fall_unconscious(cid.entity_id, "test")
	s.step(1)
	var drag: int = s.run.holds.grab(s.run, cid.entity_id, GrabHold.Kind.STYTHE_DRAG, 98, 400)
	assert_gt(drag, 0, "an unconscious one can (the Stythe collects)")
	var g: GrabHold = s.run.holds.grabs[drag]
	assert_eq(g.state, GrabHold.State.BODY)
	assert_false(s.run.holds.end_grab(s.run, drag, GrabHold.Outcome.NONE), "never ended without a listed outcome")
