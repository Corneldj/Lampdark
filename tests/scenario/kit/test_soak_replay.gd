extends "res://tests/scenario/kit/scenario_test.gd"
## FND-09's replay: a kit run's input log, and a recorded self-test soak server's log, each
## replay in-process (no clients, no network) to the same final state hash.

const Sample = preload("res://tests/scenario/kit/sample.gd")
const SELFTEST_LOG: String = "res://tests/fixtures/kit/selftest_inputs.jsonl"


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_kit_run_replays_to_the_same_hash() -> void:
	var s: Scenario = Sample.build()
	_made.append(s)
	s.step(20)
	assert_true(s.set_gate(1, true))
	s.script_rolls(3, 77, PackedInt64Array([5, 6]))
	s.step(20)
	var path: String = "user://fnd09_kit_replay.jsonl"
	assert_eq(s.save_replay(path), OK)
	var live_hash: String = s.state_hash()
	var r: Scenario = Scenario.replay(path)
	_made.append(r)
	assert_not_null(r)
	assert_eq(r.run.tick, 40)
	assert_eq(r.state_hash(), live_hash, "the replay reaches the live run's final hash")
	assert_eq(r.miners.size(), 2, "the setup steps replayed too")
	assert_true(r.mine.path_distance(r.fixture.spot("a"), r.fixture.spot("b")).distance > 0.0, "the gate was opened")


func test_the_recorded_selftest_log_replays() -> void:
	if not FileAccess.file_exists(SELFTEST_LOG):
		fail_test("missing %s: record it with tools/bots/selftest.sh --record-fixture" % SELFTEST_LOG)
		return
	var log: InputLog = InputLog.load_file(SELFTEST_LOG)
	assert_gt(log.by_tick.size(), 100, "the log holds a soak's worth of inputs")
	var r: Scenario = Scenario.replay(SELFTEST_LOG)
	_made.append(r)
	assert_eq(r.run.tick, log.end_tick)
	assert_eq(r.state_hash(), log.end_hash, "the soak server's final hash, reproduced in-process")
