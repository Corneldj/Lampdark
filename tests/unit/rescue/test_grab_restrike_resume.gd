extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-03: a pin suspended at 200 ticks (a silent pull) and resumed 90 ticks later (a ReStrike)
## times out 300 ticks after the resume, under one grab_begun.

const H = preload("res://tests/scenario/rescue/hold_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_restrike_resumes() -> void:
	var s: Scenario = make({"seed": 4, "fixture": H.hall()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.step(1)
	watch_signals(s.run.holds)
	var id: int = s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.TAPPER_PIN, 99, 500)
	s.step(200)
	var g: GrabHold = s.run.holds.grabs[id]
	assert_eq(g.elapsed, 200)
	assert_true(s.run.holds.suspend(s.run, id))
	s.step(90)
	assert_eq(g.elapsed, 200, "the crush stops while suspended")
	assert_eq(H.life(s, ann.entity_id), MinerTransitions.Life.UPRIGHT, "freed by the silent pull")
	assert_true(s.run.holds.resume(s.run, id))
	assert_eq(H.ticks_to_timeout(s, id, 400), 300, "it times out 300 ticks after the resume")
	assert_signal_emit_count(s.run.holds, "grab_begun", 1)
	assert_eq(s.run.holds.grab_of(ann.entity_id).id, id, "the same grab id")
