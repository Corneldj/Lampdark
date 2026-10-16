extends "res://tests/scenario/kit/scenario_test.gd"
## DIR-01: the Draught stays on the server and survives a save.
## - Never sent: through a build, a peak and a relax, NET-08's audit finds nothing in any client's
##   stream, and no director.* key is in the client's tuning table.
## - Saved: values, accumulators, the once-only sets and the cycle come back from NET-09's
##   save_state exactly (the peak stream's position rides with the run's streams).
## - FND-08: set_intensity sets it and the truth view's director layer shows it (dev and QA only).

const D = preload("res://tests/scenario/director/draught_world.gd")
const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")
const DebugWorld = preload("res://tests/scenario/debug/debug_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_each() -> void:
	WorldCoords.ring_override = -1


func test_never_sent_to_a_client() -> void:
	WorldCoords.ring_override = 3
	var s: Scenario = make({"seed": 801, "fixture": D.hall(), "director": true})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var ids: Array[int] = D.crew(s, ["ann", "ben"] as Array[String], ["a", "e"] as Array[String])
	D.stand_in(s, {ids[0]: 0.05})
	s.step(2)
	D.set_value(s, ids[1], 69.0)
	s.run.holds.catch(s.run, ids[1], CaughtHold.Kind.MAN_TRAP, 3)
	s.step(roundi(10.0 * Tuning.f(&"net.tick_hz")))
	assert_eq(s.run.draught.cycle.phase, DraughtCycle.Phase.RELAX, "a build, a peak and a relax were streamed")
	assert_eq(audit.violation_count, 0, "nothing of the Draught in any client's stream")
	var table: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string("res://data/tuning/_client.json")))
	for key: String in Variants.dict(table.get("keys", table)).keys():
		assert_false(key.begins_with("director."), "%s is server-only" % key)


func test_a_save_brings_it_back_exactly() -> void:
	var s: Scenario = make({"seed": 802, "fixture": D.hall(), "director": true})
	var ids: Array[int] = D.crew(s, ["ann", "ben"] as Array[String], ["a", "e"] as Array[String])
	D.stand_in(s, {ids[0]: 0.05})
	s.step(2)
	s.run.holds.catch(s.run, ids[1], CaughtHold.Kind.MAN_TRAP, 5)
	s.step(roundi(3.0 * Tuning.f(&"net.tick_hz")))
	D.set_value(s, ids[1], 72.0)
	s.step(2)
	assert_eq(s.run.draught.cycle.phase, DraughtCycle.Phase.PEAK, "mid-peak")
	var saved: Dictionary = s.run.draught.save_state()
	var bytes: PackedByteArray = var_to_bytes(saved)
	var fresh: Draught = Draught.new()
	var restored: Dictionary = Variants.dict(bytes_to_var(bytes))
	fresh.load_state(s.run, restored)
	assert_eq(_hash(fresh), _hash(s.run.draught), "every value, accumulator, once-only set and the cycle")
	assert_eq(fresh.intensity_of(ids[0]), s.run.draught.intensity_of(ids[0]))
	var ben: IntensityIntake.Record = fresh.records[ids[1]]
	assert_true(ben.counted.has("trap:5"), "the trap stays counted")


func test_set_intensity_and_the_truth_view() -> void:
	var s: Scenario = make({"seed": 803, "fixture": D.hall(), "director": true})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var ben: MinerHandle = s.add_miner("ben", s.fixture.spot("e"))
	D.stand_in(s)
	s.step(2)
	var all: Dictionary = DebugWorld.run_line(s, "set_intensity all 50")
	assert_true(Variants.flag(all["ok"]), str(all["text"]))
	assert_eq(s.state.intensity(ann), 50.0)
	assert_eq(s.state.intensity(ben), 50.0)
	var one: Dictionary = DebugWorld.run_line(s, "set_intensity %d 20" % ben.slot)
	assert_true(Variants.flag(one["ok"]), str(one["text"]))
	assert_eq(s.state.intensity(ben), 20.0)
	var publisher: TruthPublisher = null
	for system: SimSystem in s.run.stages.all_systems():
		if system is TruthPublisher:
			publisher = system as TruthPublisher
	assert_not_null(publisher, "a dev run publishes the truth view")
	var view: Dictionary = publisher.build(s.run, ann.slot, PackedStringArray(["director"]))
	var director: Dictionary = view["director"]
	assert_eq(str(director["phase"]), "build")
	var shown: Array = director["miners"]
	var row: Dictionary = shown[0]
	assert_eq(float(Variants.number(row["intensity"])), 50.0, "the truth view shows it")


static func _hash(d: Draught) -> String:
	var w: SimStateWriter = SimStateWriter.new()
	d.write_state(w)
	return w.sha256_hex()
