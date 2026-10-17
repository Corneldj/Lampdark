extends "res://tests/scenario/kit/scenario_test.gd"
## MOD-03 under NET-08's audit, over a bot lobby: a run created for a staged crew, with its plan fixed
## and a draw, sends its clients nothing that carries the seed, a run of the plan's bytes or a drawn
## name, through a spell of wandering bots, voice and a fall; and the audit's secrets rule does catch a
## message that would. (The lobby's own data: tests/unit/modes/test_lobby_metadata_has_no_secrets.gd.)

const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")
const Specs = preload("res://tests/unit/gen/template_specs.gd")
const W = preload("res://tests/scenario/net/net04_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _mine() -> FixtureMap:
	var rows: PackedStringArray = PackedStringArray(["#".repeat(44)])
	for y: int in 9:
		var row: String = "#" + ".".repeat(42) + "#"
		if y == 4:
			row = "#a" + ".".repeat(41) + "#"
		rows.append(row)
	rows.append("#".repeat(44))
	return FixtureMap.from_ascii(rows)


func test_a_bot_lobby_is_sent_no_secret() -> void:
	var s: Scenario = make({"seed": 0x5DEECE66D2B7E151, "fixture": _mine()})
	assert_true(s.run.header.run_seed >= (1 << 40) or s.run.header.run_seed < 0, "a seed worth searching for")
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	assert_eq(RunSetup.create(s.run, RunOptions.defaults(ServerConfig.Mode.FRIENDS), 3, [0, 1, 2] as Array[int]), "")
	s.run.header.draw = PackedStringArray(["dry_stores", "pale_moth"])  # as HAZ-07 will draw them
	var layouts: LbLayouts = LbLayouts.new()
	assert_true(layouts.load_pack(Specs.road_pack()))
	MineLayouts.configure(layouts, s.run.header.run_seed)
	assert_false(RunPlan.fix(layouts, s.run, PackedByteArray(), {"data_version": "test", "tuning": {}}).is_empty())
	assert_eq(s.run.header.staging, "1")
	var a: Vector2i = s.fixture.spot("a")
	var bots: Array[MinerHandle] = []
	for i: int in 3:
		bots.append(s.add_bot("bot%d" % i, a + Vector2i(4 + i * 9, 0), "wander", 31 + i))
	W.lamp(s, Vector2(a) + Vector2(9.5, 0.5), 5.0)
	W.lamp(s, Vector2(a) + Vector2(28.5, 0.5), 5.0)
	s.step(200)
	assert_true(s.run.falls.fall_unconscious(s.run, bots[2].entity_id, FallCause.Cause.ROOF_FALL))
	s.step(60)
	var r: Dictionary = audit.report()
	var checked: Dictionary = r["checked"]
	gut.p("judged: %s" % checked)
	for v: Dictionary in audit.violations.slice(0, 8):
		gut.p("VIOLATION %s" % v)
	assert_gt(int(Variants.number(checked.get("secrets", 0))), 500, "every message was searched")
	assert_eq(audit.by_rule("secrets").size(), 0, "no seed, plan or draw on the wire")
	assert_eq(audit.violation_count, 0, "and nothing else the audit forbids")
	# The rule bites: a message carrying the seed's bytes, then one carrying a drawn name.
	var le: PackedByteArray = PackedByteArray()
	le.resize(8)
	le.encode_s64(0, s.run.header.run_seed)
	var peer: int = s.net.sessions.welcomed()[0].peer
	audit.on_send(peer, Lane.Id.CONTROL, Protocol.frame(Protocol.Msg.MANUAL, PackedByteArray([1, 2]) + le))
	assert_eq(audit.by_rule("secrets").size(), 1, "a message carrying the seed is caught")
	audit.on_send(peer, Lane.Id.CONTROL, Protocol.frame(Protocol.Msg.MANUAL, "pale_moth".to_utf8_buffer()))
	assert_eq(audit.by_rule("secrets").size(), 2, "and one naming the draw")
