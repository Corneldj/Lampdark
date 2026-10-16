extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-03: the Pull stays on the server. Through a build with miners alone and in company, marked and
## ebbing, NET-08's audit finds nothing in any client's stream and no pull.* key is in the client's
## tuning table. FND-08's set_pull sets it and the truth view's director layer shows it (dev and QA).

const D = preload("res://tests/scenario/director/draught_world.gd")
const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")
const DebugWorld = preload("res://tests/scenario/debug/debug_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_never_sent_to_a_client() -> void:
	var s: Scenario = make({"seed": 2701, "fixture": D.hall(), "director": true})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var ids: Array[int] = D.crew(s, ["ann", "ben", "cat"] as Array[String], ["a", "b", "f"] as Array[String])
	D.stand_in(s)
	s.run.pull.ring_of = func(_m: int) -> int: return 4
	s.step(2)
	s.run.pull.set_value(ids[2], 49.0)
	s.step(200)
	assert_gt(s.run.pull.value_of(ids[2]), 50.0, "Cat, alone, was marked")
	s.run.creatures.gate.hunt_ended.emit(null, ids[2], "x")
	s.step(40)
	assert_eq(audit.violation_count, 0, "nothing of the Pull in any client's stream")
	var table: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string("res://data/tuning/_client.json")))
	for key: String in Variants.dict(table.get("keys", table)).keys():
		assert_false(key.begins_with("pull."), "%s is server-only" % key)


func test_set_pull_and_the_truth_view() -> void:
	var s: Scenario = make({"seed": 2702, "fixture": D.hall(), "director": true})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var ben: MinerHandle = s.add_miner("ben", s.fixture.spot("f"))
	D.stand_in(s)
	s.step(2)
	assert_true(Variants.flag(DebugWorld.run_line(s, "set_pull all 60")["ok"]))
	assert_almost_eq(s.state.pull(ann), 60.0, 0.01)
	assert_true(Variants.flag(DebugWorld.run_line(s, "set_pull %d 10" % ben.slot)["ok"]))
	assert_almost_eq(s.state.pull(ben), 10.0, 0.01)
	var publisher: TruthPublisher = null
	for system: SimSystem in s.run.stages.all_systems():
		if system is TruthPublisher:
			publisher = system as TruthPublisher
	var view: Dictionary = publisher.build(s.run, ann.slot, PackedStringArray(["director"]))
	var director: Dictionary = view["director"]
	var shown: Array = director["miners"]
	var row: Dictionary = shown[0]
	assert_almost_eq(float(Variants.number(row["pull"])), 60.0, 0.05, "the truth view shows it")
