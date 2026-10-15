extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-10, under NET-08's audit: a mark is sent to a client only on a tile it sees lit to 0.30, with
## its glyph; at 0.25 the tile arrives bare, behind the miner nothing arrives, and a mark is never a
## token. Its author never leaves the server.

const C = preload("res://tests/unit/mnr/chalk_world.gd")
const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_seen_at_0_30_never_below_or_behind() -> void:
	var s: Scenario = make({"seed": 1021, "fixture": C.B.room()})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var lit: Vector2i = Vector2i(6, 3)
	var dim: Vector2i = Vector2i(8, 3)
	var behind: Vector2i = Vector2i(2, 3)
	s.run.light.grid.add_area("t30", LbLightGrid.COLOUR_WHITE, 0, 0.30, [lit, behind])
	s.run.light.grid.add_area("t25", LbLightGrid.COLOUR_WHITE, 0, 0.25, [dim])
	var bob: MinerHandle = C.miner(s, "bob", Vector2i(4, 3), 0.0)
	s.step(3)
	var ann: int = 4242
	for t: Vector2i in [lit, dim, behind]:
		s.run.chalk.store.put(s.run, t, ChalkMarks.Surface.FLOOR, ChalkMarks.glyph(ChalkMarks.Kind.DIGIT_4), ann)
	s.run.chalk.store.put(s.run, lit, ChalkMarks.Surface.SOUTH, ChalkMarks.glyph(ChalkMarks.Kind.ARROW, 4), ann)
	var got: Dictionary = {}
	s.client(bob).on_decoded = func(d: FrameDecoder.Decoded) -> void: got["tiles"] = d.view.tiles.duplicate()
	var tokens_before: int = s.run.registry.count()
	s.step(6)
	var tiles: Dictionary = got.get("tiles", {})
	assert_true(tiles.has(lit), "the 0.30 tile is seen")
	var rec: PackedByteArray = tiles[lit]
	assert_ne(rec[2] & TileBits.DECAL_CHALK, 0, "with its chalk")
	assert_eq(rec.slice(3), PackedByteArray([ChalkMarks.glyph(ChalkMarks.Kind.DIGIT_4), 0, 0, ChalkMarks.glyph(ChalkMarks.Kind.ARROW, 4), 0]),
		"the floor's 4 and the south face's arrow west")
	assert_true(tiles.has(dim), "the 0.25 tile arrives")
	var bare: PackedByteArray = tiles[dim]
	assert_eq(bare[2] & TileBits.DECAL_CHALK, 0, "but bare: no chalk below 0.30")
	assert_eq(bare.size(), 3, "and no glyph bytes")
	assert_false(tiles.has(behind), "behind him: nothing")
	assert_eq(s.run.registry.count(), tokens_before, "a mark is no entity, so never a token")
	for v: Dictionary in audit.violations.slice(0, 8):
		gut.p(str(v))
	assert_eq(audit.violation_count, 0, "no chalk sent unseen or below 0.30")
