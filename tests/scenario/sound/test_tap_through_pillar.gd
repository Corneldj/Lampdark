extends "res://tests/scenario/kit/scenario_test.gd"
## SND-12 (§6.6), under NET-08's audit: two roads with a rock mass between them and no way round.
## Ann taps the rock; Bob, 18 tiles away beyond it, hears the tap at his own wall face toward her,
## and she is heard; Dan, 21 tiles away, gets nothing.

const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")
const W = preload("res://tests/unit/sound/signal_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _rock_band() -> FixtureMap:
	var rows: PackedStringArray = ["#".repeat(32), "#" + ".".repeat(30) + "#"]
	for _i: int in 17:
		rows.append("#".repeat(32))
	rows.append("#" + ".".repeat(30) + "#")
	rows.append("#".repeat(32))
	return FixtureMap.from_ascii(rows)


func test_through_the_rock_to_eighteen_not_twenty_one() -> void:
	var s: Scenario = make({"seed": 1151, "fixture": _rock_band()})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var ann: MinerHandle = W.miner(s, "ann", Vector2i(2, 1), 90.0, false)  # facing the rock to the south
	var bob: MinerHandle = W.miner(s, "bob", Vector2i(2, 19), 270.0, false)
	var dan: MinerHandle = W.miner(s, "dan", Vector2i(13, 19), 270.0, false)
	s.step(3)
	assert_almost_eq(Vector2(2, 1).distance_to(Vector2(2, 19)), 18.0, 1e-6)
	assert_gt(Vector2(2, 1).distance_to(Vector2(13, 19)), 21.0)
	var heard_before: int = s.run.heard.heard_log.size()
	W.tap_press(s, ann)
	s.step(8)
	var t: Dictionary = s.run.rock_taps.taps[s.run.rock_taps.taps.size() - 1]
	assert_false(Variants.flag(t["refused"]), "she taps the rock")
	var to: Dictionary = {}
	for d: Dictionary in s.run.rock_taps.rock_deliveries:
		to[int(Variants.number(d["listener"]))] = d["face"]
	gut.p("through the rock: %s" % [to])
	assert_true(to.has(bob.slot), "Bob, 18 tiles beyond the rock, gets it")
	var face: Vector2i = to[bob.slot]
	assert_eq(face, Vector2i(2, 18), "at his own wall face, toward her")
	assert_false(to.has(dan.slot), "Dan, 21 tiles away, does not")
	var bob_heard: Array[Dictionary] = []
	for e: Dictionary in s.client(bob).audio_events(0, s.run.tick):
		if int(Variants.number(e["type"])) == NoiseTypes.Type.ROCK_TAP:
			bob_heard.append(e)
	assert_eq(bob_heard.size(), 1, "his client plays it")
	var at: Vector2 = bob_heard[0]["apparent"]
	assert_lt(at.distance_to(Vector2(2.5, 18.5)), 0.6, "from the wall face")
	for e: Dictionary in s.client(dan).audio_events(0, s.run.tick):
		assert_ne(int(Variants.number(e["type"])), NoiseTypes.Type.ROCK_TAP, "Dan's plays nothing")
	var marked: bool = false
	for row: Dictionary in s.run.heard.heard_log.slice(heard_before):
		marked = marked or (int(Variants.number(row["slot"])) == ann.slot and StringName(str(row["cause"])) == &"tap")
	assert_true(marked, "the tap makes her heard")
	for v: Dictionary in audit.violations.slice(0, 8):
		gut.p("VIOLATION %s" % v)
	assert_eq(audit.violation_count, 0)
