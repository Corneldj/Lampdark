extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-03's traps: a caught miner is held until freed; an unconscious one stays held until
## release_caught.

const H = preload("res://tests/scenario/rescue/hold_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_caught_and_freed() -> void:
	var s: Scenario = make({"seed": 5, "fixture": H.hall()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.step(1)
	watch_signals(s.run.holds)
	assert_true(s.run.holds.catch(s.run, ann.entity_id, CaughtHold.Kind.MAN_TRAP, 7))
	s.step(1)
	assert_eq(H.life(s, ann.entity_id), MinerTransitions.Life.CAUGHT)
	assert_signal_emit_count(s.run.holds, "caught_begun", 1)
	s.run.miner_state.fall_unconscious(ann.entity_id, "test")
	s.step(100)
	assert_eq(H.life(s, ann.entity_id), MinerTransitions.Life.UNCONSCIOUS)
	assert_true(s.run.holds.is_held(ann.entity_id), "an unconscious body stays in the trap")
	assert_eq(s.run.holds.caught_in(ann.entity_id).trap_id, 7)
	assert_true(s.run.holds.release_caught(s.run, ann.entity_id, CaughtHold.Outcome.FREED))
	s.step(1)
	assert_false(s.run.holds.is_held(ann.entity_id))
	assert_signal_emit_count(s.run.holds, "caught_ended", 1)
