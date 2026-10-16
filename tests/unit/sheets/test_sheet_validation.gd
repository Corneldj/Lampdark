extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-14: the server holds the map table to its rules (GDD §15.11), whatever a client sends. An
## 11th commit within a second is refused; so are an over-long stroke, a cramped one, a 41-character
## label, and any commit from a miner not at the table or seated at the board. In a public lobby the
## rubber touches only its own miner's strokes, and a blocker is never sent the blocked player's
## strokes or labels, finished or as made.

const T = preload("res://tests/scenario/sheets/table_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _short(at: Vector2) -> PackedVector2Array:
	return T.line(at, at + Vector2(100, 0), 2)


func test_an_eleventh_commit_within_a_second_is_refused() -> void:
	var s: Scenario = T.camp(1401, self)
	var ann: MinerHandle = T.walk_up(s, "ann")
	assert_eq(s.run.closeups.kind_of(ann.entity_id), CloseupKind.Kind.MAP_TABLE, "Ann opened the table")
	var msg: PackedByteArray = PackedByteArray()
	for i: int in 11:
		msg.append_array(SheetCodec.commit_stroke(i + 1, _short(Vector2(0, i * 64))))
	T.send_raw(ann, msg)
	s.step(3)
	assert_eq(s.run.sheets.table.sheet.count(), 10, "ten in the second")
	assert_eq(T.refused_whys(s), ["rate"] as Array[String], "the eleventh refused")
	var dropped: Array[Dictionary] = T.ops_of(ann, [SheetCodec.Op.DROPPED])
	assert_eq(dropped.size(), 1)
	assert_eq(int(Variants.number(dropped[0]["seq"])), 11, "and Ann's client told it marked nothing")
	s.step(20)
	T.send_raw(ann, SheetCodec.commit_stroke(12, _short(Vector2(0, 2000))))
	s.step(3)
	assert_eq(s.run.sheets.table.sheet.count(), 11, "a second later the pencil marks again")


func test_the_client_never_sends_an_eleventh_within_its_window() -> void:
	var s: Scenario = T.camp(1402, self)
	var ann: MinerHandle = T.walk_up(s, "ann")
	for i: int in 11:
		T.draw(ann, _short(Vector2(0, i * 64)))
	assert_eq(ann.connection.sheet.outbox_size(), 1, "the eleventh waits")
	assert_eq(ann.connection.sheet.pending.size(), 11, "though Ann sees all eleven at once")
	s.step(30)
	assert_eq(s.run.sheets.table.sheet.count(), 11, "it goes when the window allows")
	assert_eq(s.run.sheets.refused.size(), 0, "nothing refused")
	assert_eq(ann.connection.sheet.pending.size(), 0, "every one answered")
	assert_eq(ann.connection.sheet.sheet.count(), 11, "and held as the server's")


func test_strokes_and_labels_out_of_their_caps_are_refused() -> void:
	var s: Scenario = T.camp(1403, self)
	var ann: MinerHandle = T.walk_up(s, "ann")
	var max_points: int = Tuning.i(&"mine.sheet_stroke_max_points")
	T.send_raw(ann, SheetCodec.commit_stroke(1, T.line(Vector2(0, 0), Vector2(20 * max_points, 0), max_points)))
	T.send_raw(ann, SheetCodec.commit_stroke(2, T.line(Vector2(0, 512), Vector2(20 * (max_points - 1), 512), max_points - 1)))
	T.send_raw(ann, SheetCodec.commit_stroke(3, PackedVector2Array([Vector2(0, 1024), Vector2(10, 1024)])))
	T.send_raw(ann, SheetCodec.commit_stroke(4, PackedVector2Array([Vector2(0, 1536), Vector2(100, 1636)])))
	T.send_raw(ann, SheetCodec.commit_label(5, Vector2(0, 2048), "x".repeat(41)))
	T.send_raw(ann, SheetCodec.commit_label(6, Vector2(0, 2560), "x".repeat(40)))
	s.step(3)
	assert_eq(T.refused_whys(s), ["too long", "spacing", "spacing", "label"] as Array[String],
		"65 points, a 10-unit step, a 141-unit step and 41 characters")
	assert_eq(s.run.sheets.table.sheet.count(), 2, "64 points and 40 characters are on the sheet")
	assert_eq(ann.connection.sheet.sheet.count(), 0, "Ann's own commits come back as answers, not copies")


func test_nobody_draws_away_from_the_table_or_seated_at_the_board() -> void:
	var s: Scenario = T.camp(1404, self)
	var deck: Vector2i = Basecamp.fixture(T.C.SEED, "cage_deck", s.run.base_camp.side)[0]["position"]
	var ann: MinerHandle = s.add_miner("ann", deck)
	var op: MinerHandle = T.W.beside(s, "op", CloseupKind.Kind.SWITCHBOARD)
	T.W.interact(s, op, roundi((Tuning.f(&"phones.seat_s") + 0.5) * Tuning.f(&"net.tick_hz")))
	s.step(roundi((Tuning.f(&"phones.seat_s") + 1.0) * Tuning.f(&"net.tick_hz")))
	assert_eq(s.run.closeups.kind_of(op.entity_id), CloseupKind.Kind.SWITCHBOARD, "the operator is seated")
	T.send_raw(op, SheetCodec.commit_stroke(1, _short(Vector2.ZERO)))
	T.send_raw(ann, SheetCodec.commit_stroke(1, _short(Vector2.ZERO)))
	T.send_raw(op, SheetCodec.commit_label(2, Vector2.ZERO, "line 4: the pump"))
	s.step(3)
	assert_eq(T.refused_whys(s), ["seated", "not at the table", "seated"] as Array[String])
	assert_eq(s.run.sheets.table.sheet.count(), 0)


func test_in_public_the_rubber_touches_only_its_own_miners_strokes() -> void:
	var s: Scenario = T.camp(1405, self, ServerConfig.Mode.PUBLIC)
	var ann: MinerHandle = T.walk_up(s, "ann")
	var bob: MinerHandle = T.walk_up(s, "bob", 1)
	T.draw(ann, T.line(Vector2(0, 0), Vector2(600, 0), 6))
	T.draw(bob, T.line(Vector2(0, 30), Vector2(600, 30), 6))
	s.step(5)
	assert_eq(s.run.sheets.table.sheet.count(), 2)
	var before: int = s.run.sheets.table.sheet.digest()
	# Bob rubs across both lines: only his own is touched.
	bob.connection.sheet.rub(PackedVector2Array([Vector2(300, 15)]))
	s.step(5)
	var left: Array = s.run.sheets.table.sheet.strokes.values()
	assert_eq(left.size(), 3, "Ann's line whole, Bob's in two")
	assert_true(s.run.sheets.table.sheet.has(1), "Ann's stroke untouched")
	assert_ne(s.run.sheets.table.sheet.digest(), before)
	# A stranger who never drew rubs nothing at all.
	var cid: MinerHandle = T.at_table(s, "cid", 2)
	var count: int = s.run.sheets.table.sheet.count()
	cid.connection.sheet.rub(PackedVector2Array([Vector2(100, 0), Vector2(100, 30)]))
	s.step(5)
	assert_eq(s.run.sheets.table.sheet.count(), count, "rubbing out another's stroke changes nothing")
	ann.connection.sheet.rub(PackedVector2Array([Vector2(100, 0)]))
	s.step(5)
	assert_false(s.run.sheets.table.sheet.has(1), "Ann rubs out her own")


func test_in_a_friends_lobby_anyone_rubs_anything() -> void:
	var s: Scenario = T.camp(1406, self)
	var ann: MinerHandle = T.walk_up(s, "ann")
	var bob: MinerHandle = T.walk_up(s, "bob", 1)
	T.draw(ann, T.line(Vector2(0, 0), Vector2(600, 0), 6))
	s.step(5)
	bob.connection.sheet.rub(PackedVector2Array([Vector2(300, 0)]))
	s.step(5)
	assert_false(s.run.sheets.table.sheet.has(1), "Bob rubs through Ann's line")
	assert_eq(s.run.sheets.table.sheet.count(), 2, "leaving its two ends")


func test_a_blocker_never_receives_the_blocked_players_strokes() -> void:
	var s: Scenario = T.camp(1407, self, ServerConfig.Mode.PUBLIC)
	var ann: MinerHandle = T.walk_up(s, "ann")
	var bob: MinerHandle = T.walk_up(s, "bob", 1)
	var cid: MinerHandle = T.at_table(s, "cid", 2)
	var blocking: Array[bool] = [true]
	s.run.sheets.sync.blocks_of = func(slot: int) -> Array:
		return ["ann"] if slot == bob.slot and blocking[0] else []
	s.step(2)
	# Ann's stroke as she makes it, then finished, and a label.
	var stroke: PackedVector2Array = T.line(Vector2(0, 0), Vector2(600, 0), 6)
	ann.connection.sheet.sketching(1, stroke.slice(0, 3))
	s.step(2)
	ann.connection.sheet.sketching(1, stroke)
	s.step(4)
	T.draw(ann, stroke)
	ann.connection.sheet.commit_label(Vector2(0, 300), "Here be the Stythe", Transport.now_usec())
	T.draw(cid, T.line(Vector2(0, 600), Vector2(600, 600), 6))
	s.step(8)
	assert_gt(T.ops_of(cid, [SheetCodec.Op.PEN]).size(), 0, "Cid saw Ann's stroke as it was made")
	assert_eq(T.ops_of(bob, [SheetCodec.Op.PEN]).size(), 0, "Bob never did")
	assert_eq(cid.connection.sheet.sheet.count(), 3, "Cid holds all three")
	assert_eq(bob.connection.sheet.sheet.count(), 1, "Bob only Cid's")
	for d: Dictionary in T.ops_of(bob, [SheetCodec.Op.ADD_STROKE, SheetCodec.Op.ADD_LABEL]):
		assert_eq(int(Variants.number(d["id"])), 3, "nothing of Ann's in Bob's stream")
	# Lifted, the block's strokes come.
	blocking[0] = false
	s.step(10)
	assert_eq(bob.connection.sheet.sheet.count(), 3, "unblocked, Bob is sent them")
	assert_eq(bob.connection.sheet.sheet.digest(), cid.connection.sheet.sheet.digest())
