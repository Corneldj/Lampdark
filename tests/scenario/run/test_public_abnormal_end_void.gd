extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-11 with NET-09 (Gameplay §13.11, GDD §15.10): an abnormal end records no outcome. A public
## run's is void: no outcome is ever set and no run_ended is emitted, even if the cage were to
## surface after. A friends run's leaves its last snapshot to resume, its outcomes unrecorded.

const K = preload("res://tests/unit/lift/cage_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_public_abnormal_end_is_void() -> void:
	var s: Scenario = make({"seed": 11501, "fixture": K.E.T.C.scenario_fixture(), "mode": ServerConfig.Mode.PUBLIC})
	K.ready(s)
	var ann: MinerHandle = K.aboard(s, "ann", 0)
	var ended: Array[Dictionary] = []
	s.run.outcomes.run_ended.connect(func(rec: Dictionary) -> void: ended.append(rec))
	assert_true(s.run.saves.end_abnormally(s.run, "the host quit").is_empty(), "nothing written")
	assert_true(s.run.outcomes.voided)
	s.run.miner_state.fall_unconscious(ann.entity_id, "test")
	s.step(10)
	s.run.cage.cage_surfaced.emit({})
	s.step(2)
	assert_eq(ended.size(), 0, "no run_ended for a void run")
	assert_eq(s.run.miner_state.miner(ann.entity_id).outcome, MinerTransitions.Outcome.NONE, "no outcome")


func test_a_friends_abnormal_end_records_none() -> void:
	var s: Scenario = make({"seed": 11502, "fixture": K.E.T.C.scenario_fixture(), "saves": true})
	K.ready(s)
	var ann: MinerHandle = K.aboard(s, "ann", 0)
	var row: Dictionary = s.run.saves.end_abnormally(s.run, "the host quit")
	assert_false(row.is_empty(), "its last snapshot, to resume")
	s.step(3)
	assert_false(s.run.outcomes.ended)
	assert_eq(s.run.miner_state.miner(ann.entity_id).outcome, MinerTransitions.Outcome.NONE, "no outcome recorded")
