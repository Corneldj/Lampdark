extends "res://tests/scenario/kit/scenario_test.gd"
## NET-09's save budgets and cadence: a snapshot every net.snapshot_interval_s (±1 tick) in a friends
## run, never during a grab under way; each section held to its budget, one over it an error in a
## debug build (logged in release); a run's save well inside 50 MB; the capture measured, inside a
## tick. The three-hour Full-run size is judged by FND-04's record nightly (record_budget_nightly).

const S = preload("res://tests/scenario/net/save_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_snapshot_every_interval() -> void:
	S.clear(961)
	var s: Scenario = make(S.cfg(961))
	S.miner(s, "ann", Vector2i(3, 3))
	S.miner(s, "bob", Vector2i(8, 3))
	var every: int = roundi(Tuning.f(&"net.snapshot_interval_s") * Tuning.f(&"net.tick_hz"))
	assert_true(S.until_saved(s, 4, every * 5))
	var w: Array[Dictionary] = s.run.saves.written
	for i: int in range(1, w.size()):
		var gap: int = int(Variants.number(w[i]["tick"])) - int(Variants.number(w[i - 1]["tick"]))
		assert_almost_eq(gap, every, 1, "snapshot %d: every %d ticks (±1)" % [i, every])
		assert_eq(int(Variants.number(w[i]["seq"])), i + 1, "numbered in order")
	var usec: Array[int] = []
	for row: Dictionary in w:
		usec.append(int(Variants.number(row["capture_usec"])))
	usec.sort()
	gut.p("capture %s us; save %d bytes %s" % [str(usec), int(Variants.number(w[0]["bytes"])), str(w[w.size() - 1]["sections"])])
	var tick_usec: int = roundi(1000000.0 / Tuning.f(&"net.tick_hz"))
	assert_lt(usec[usec.size() - 1], tick_usec, "a capture fits inside a tick")
	assert_lt(int(Variants.number(w[w.size() - 1]["bytes"])), roundi(Tuning.f(&"net.save_budget_mb") * 1048576.0))
	assert_eq(s.run.saves.breaches.size(), 0)


func test_night_shift_is_saved_too() -> void:
	S.clear(964)
	var s: Scenario = make(S.cfg(964, ServerConfig.Mode.NIGHTSHIFT))
	S.miner(s, "ann", Vector2i(3, 3))
	var every: int = roundi(Tuning.f(&"net.snapshot_interval_s") * Tuning.f(&"net.tick_hz"))
	assert_true(S.until_saved(s, 2, every * 3))
	var gap: int = int(Variants.number(s.run.saves.written[1]["tick"])) - int(Variants.number(s.run.saves.written[0]["tick"]))
	assert_almost_eq(gap, every, 1)
	assert_true(FileAccess.file_exists(S.snapshot_path(s)), "on the offline disk")


func test_no_snapshot_during_a_grab() -> void:
	S.clear(962)
	var s: Scenario = make(S.cfg(962))
	var ann: MinerHandle = S.miner(s, "ann", Vector2i(3, 3))
	S.miner(s, "bob", Vector2i(8, 3))
	assert_true(Snapshot.may_capture(s.run))
	var every: int = roundi(Tuning.f(&"net.snapshot_interval_s") * Tuning.f(&"net.tick_hz"))
	# A grab under way across the moment the snapshot falls due (a stand-in hold: no creature).
	s.step(every - 20)
	var id: int = s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.TAPPER_PIN, 0, every * 2)
	assert_ne(id, 0)
	s.step(2)
	assert_false(Snapshot.may_capture(s.run), "not while the grab is live")
	s.step(40)
	assert_eq(s.run.saves.written.size(), 0, "the snapshot waits")
	var hold: GrabHold = s.run.holds.grabs[id]
	hold.state = GrabHold.State.ENDED
	s.step(2)
	assert_eq(s.run.saves.written.size(), 1, "taken once the grab is over")


func test_a_section_over_its_budget_is_an_error() -> void:
	S.clear(963)
	var s: Scenario = make({"seed": 963, "fixture": S.B.room(), "saves": true,
		"overrides": {"net.save_budget_snapshot_mb": 0}})
	S.miner(s, "ann", Vector2i(3, 3))
	s.step(2)
	var row: Dictionary = s.run.saves.snapshot(s.run)
	assert_false(row.is_empty(), "still written")
	assert_eq(s.run.saves.breaches.size(), 1)
	assert_eq(str(s.run.saves.breaches[0]["section"]), "snapshot")
	assert_push_error("over its")
