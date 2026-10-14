extends "res://tests/scenario/kit/scenario_test.gd"
## NET-08: a clean run passes the audit with no violations and no tolerated exceptions: miners
## walking, running and turning under lamps of their own and on the road, a Moth and a Stythe stand-in in
## the fringe and the dark, voice at every band, a fall with its knocks; every rule judged records.

const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")
const W = preload("res://tests/scenario/net/net04_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _mine() -> FixtureMap:
	var rows: PackedStringArray = PackedStringArray(["#".repeat(44)])
	for y: int in 9:
		var row: String = "#" + ".".repeat(42) + "#"
		if y == 4:
			row = "#a" + ".".repeat(12) + "##.#" + ".".repeat(8) + "B" + ".".repeat(16) + "#"
		rows.append(row)
	rows.append("#".repeat(44))
	return FixtureMap.from_ascii(rows)


func test_a_clean_run_passes() -> void:
	var s: Scenario = make({"seed": 808, "fixture": _mine()})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var ben: MinerHandle = s.add_miner("ben", a + Vector2i(6, -2))
	var cat: MinerHandle = s.add_miner("cat", a + Vector2i(20, 2))
	W.lamp(s, Vector2(a) + Vector2(9.5, 0.5), 4.0)
	W.lamp(s, Vector2(a) + Vector2(30.5, -2.5), 6.0)
	s.place_creature(WorldIds.EntityKind.MOTH, a + Vector2i(14, 3))
	s.place_stand_in(WorldIds.EntityKind.STYTHE, a + Vector2i(24, -3))
	s.step(5)
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.WALK, 60).say(2, 20)
	ben.at(s.run.tick).face(180.0).wait(10).move(90.0, InputRecord.Gait.RUN, 20).face(0.0).say(3, 10)
	cat.at(s.run.tick).face(180.0).wait(30).face(270.0).say(1, 15)
	s.step(80)
	assert_true(s.run.falls.fall_unconscious(s.run, cat.entity_id, FallCause.Cause.ROOF_FALL))
	ann.at(s.run.tick).move(180.0, InputRecord.Gait.WALK, 30).face(45.0)
	s.step(80)
	var r: Dictionary = audit.report()
	gut.p("judged: %s" % r["checked"])
	for v: Dictionary in audit.violations.slice(0, 12):
		gut.p("VIOLATION %s" % v)
	assert_eq(audit.violation_count, 0, "a clean run: no violations")
	var checked: Dictionary = r["checked"]
	for rule: String in ["frame", "tile", "geometry", "entity", "glow", "audio", "voice", "knocks", "handshake"]:
		assert_gt(int(Variants.number(checked.get(rule, 0))), 0, "%s records were judged" % rule)
