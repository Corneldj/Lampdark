extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-14: the sheet syncs live to every conscious client but its strokes as made go only to the
## miners at the table (GDD §15.3, Gameplay §14.3). Two at the table see each other's strokes as
## made within 250 ms at a 120 ms round trip (Proposed); a committed stroke reaches a conscious
## miner anywhere, unsigned; an unconscious miner's client gets no sheet data at all and is
## resynced on coming round.

const T = preload("res://tests/scenario/sheets/table_world.gd")
const RTT_MS: int = 120
const LATENCY_MS: float = 250.0


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_two_at_the_table_see_each_others_strokes_as_made_within_250_ms() -> void:
	var s: Scenario = T.camp(1501, self)
	var ann: MinerHandle = T.walk_up(s, "ann")
	var bob: MinerHandle = T.walk_up(s, "bob", 1)
	ann.link(RTT_MS, 0.0)
	bob.link(RTT_MS, 0.0)
	s.step(20)
	# Ann's hand moves on 40 points a second for 1.5 s; Bob's client notes when each point shows.
	var drawn: Array[Vector2] = []
	var added_usec: Array[int] = []
	var seen_usec: Array[int] = []
	var start: int = Transport.now_usec()
	var spacing: float = Tuning.f(&"mine.sheet_point_spacing_units") + 4.0
	s.on_poll = func(_sc: Scenario) -> void:
		var now: int = Transport.now_usec()
		while drawn.size() < 60 and now - start >= drawn.size() * 25000:
			drawn.append(Vector2(drawn.size() * spacing, 0.0))
			added_usec.append(now)
			ann.connection.sheet.sketching(1, PackedVector2Array(drawn))
		for raw: Variant in bob.connection.sheet.pens.keys():
			var p: Dictionary = bob.connection.sheet.pens[raw]
			var have: PackedVector2Array = p["points"]
			while seen_usec.size() < have.size():
				seen_usec.append(now)
	s.step(50)
	s.on_poll = Callable()
	assert_eq(added_usec.size(), 60)
	assert_eq(seen_usec.size(), 60, "every point reached Bob as it was made")
	var worst: float = 0.0
	for i: int in mini(added_usec.size(), seen_usec.size()):
		worst = maxf(worst, (seen_usec[i] - added_usec[i]) / 1000.0)
	gut.p("worst point-to-screen latency at %d ms RTT: %.1f ms" % [RTT_MS, worst])
	assert_lte(worst, LATENCY_MS, "within 250 ms")
	assert_eq(bob.connection.sheet.pens.size(), 1, "one stroke in progress, under a pen that names nobody")
	# Committed, the stroke replaces its in-progress line.
	T.draw(ann, PackedVector2Array(drawn))
	s.step(20)
	assert_eq(bob.connection.sheet.pens.size(), 0, "the pen lifted")
	assert_eq(bob.connection.sheet.sheet.count(), 1, "the stroke is on Bob's sheet")


func test_a_committed_stroke_reaches_a_miner_anywhere_unsigned() -> void:
	var s: Scenario = T.camp(1502, self)
	var ann: MinerHandle = T.walk_up(s, "ann")
	var deck: Vector2i = Basecamp.fixture(T.C.SEED, "cage_deck", s.run.base_camp.side)[0]["position"]
	var cat: MinerHandle = s.add_miner("cat", deck)
	s.step(10)
	var stroke: PackedVector2Array = T.line(Vector2(-300, 40), Vector2(300, 40), 6)
	ann.connection.sheet.sketching(7, stroke)
	s.step(4)
	T.draw(ann, stroke)
	ann.connection.sheet.commit_label(Vector2(0, -200), "the shaft", Transport.now_usec())
	s.step(60)
	assert_eq(s.run.closeups.kind_of(cat.entity_id), CloseupKind.Kind.NONE, "Cat is not at the table")
	assert_eq(cat.connection.sheet.sheet.count(), 2, "but holds the stroke and the label")
	assert_eq(T.ops_of(cat, [SheetCodec.Op.PEN, SheetCodec.Op.PEN_UP]).size(), 0, "never a stroke as made")
	for d: Dictionary in T.ops_of(cat, [SheetCodec.Op.ADD_LABEL]):
		assert_eq(str(d["author"]), "", "a friends lobby's label carries no author")
	for m: Dictionary in T.sheet_messages(cat):
		assert_eq(int(Variants.number(m["lane"])), Lane.Id.BULK, "the sync goes reliably on the bulk lane")
	assert_eq(cat.connection.sheet.sheet.digest(), s.run.sheets.table.sheet.digest(), "as the server holds it")


func test_the_fallen_get_no_sheet_data_and_are_resynced_coming_round() -> void:
	var s: Scenario = T.camp(1503, self)
	var ann: MinerHandle = T.walk_up(s, "ann")
	var deck: Vector2i = Basecamp.fixture(T.C.SEED, "cage_deck", s.run.base_camp.side)[0]["position"]
	var dan: MinerHandle = s.add_miner("dan", deck)
	T.draw(ann, T.line(Vector2(0, 0), Vector2(600, 0), 6))
	T.draw(ann, T.line(Vector2(0, 300), Vector2(600, 300), 6))
	s.step(40)
	assert_eq(dan.connection.sheet.sheet.count(), 2)
	assert_true(s.run.falls.fall_unconscious(s.run, dan.entity_id, FallCause.Cause.ROOF_FALL))
	s.step(2)
	var fell_at: int = s.run.tick
	ann.connection.sheet.sketching(3, T.line(Vector2(0, 900), Vector2(300, 900), 3))
	s.step(3)
	T.draw(ann, T.line(Vector2(0, 600), Vector2(600, 600), 6))
	ann.connection.sheet.rub(PackedVector2Array([Vector2(0, 0)]))
	ann.connection.sheet.commit_label(Vector2(0, 1200), "dan fell here", Transport.now_usec())
	s.step(100)
	var while_down: int = 0
	for m: Dictionary in T.sheet_messages(dan):
		if int(Variants.number(m["tick"])) > fell_at:
			while_down += 1
	assert_eq(while_down, 0, "nothing of the sheet while unconscious")
	assert_eq(dan.connection.sheet.sheet.count(), 2, "Dan's copy as he fell")
	s.run.miner_state.revive(dan.entity_id, &"test")
	s.step(60)
	assert_eq(s.run.miner_state.life(dan.entity_id), MinerTransitions.Life.UPRIGHT, "Dan came round")
	assert_eq(dan.connection.sheet.sheet.digest(), s.run.sheets.table.sheet.digest(), "resynced: removals, pieces and the new")
	assert_eq(T.ops_of(dan, [SheetCodec.Op.RESET]).size(), 1, "against what he held, not from scratch")


func test_a_watcher_never_sees_the_table() -> void:
	var s: Scenario = T.camp(1504, self)
	var ann: MinerHandle = T.walk_up(s, "ann")
	var deck: Vector2i = Basecamp.fixture(T.C.SEED, "cage_deck", s.run.base_camp.side)[0]["position"]
	var dan: MinerHandle = s.add_miner("dan", deck)
	s.step(5)
	assert_true(s.run.falls.fall_unconscious(s.run, dan.entity_id, FallCause.Cause.ROOF_FALL))
	s.step(2)
	dan.at(s.run.tick + 1).press(ActionRecord.Kind.WATCH, 1)
	s.step(5)
	var fallen: DarkSystem.Fallen = s.run.dark.fallen[dan.entity_id]
	assert_eq(fallen.watching, ann.slot, "Dan watches Ann at the table")
	var fell_at: int = s.run.tick
	for i: int in 30:
		T.draw(ann, T.line(Vector2(0, i * 64), Vector2(600, i * 64), 6))
		s.step(20)
	var delayed: Dictionary = RecordReaders.delayed_view(s.run.record, ann.slot, 8.0)
	assert_false(delayed.is_empty())
	var v: ReceivedView = delayed["view"]
	assert_eq(v.tiles.size() + v.entities.size(), 0, "what a watcher is given of Ann reading the table: nothing")
	var sheet_to_dan: int = 0
	for m: Dictionary in T.sheet_messages(dan):
		if int(Variants.number(m["tick"])) > fell_at:
			sheet_to_dan += 1
	assert_eq(sheet_to_dan, 0, "and nothing of the sheet")
	assert_gt(s.run.sheets.table.sheet.count(), 20, "while Ann drew")


## The sheet starts blank in every run and nothing of the mine or the seed is ever drawn on it: two
## runs of different seeds send their clients the same sheet stream until somebody draws.
func test_nothing_of_the_mine_reaches_the_sheet() -> void:
	var streams: Array[String] = []
	for seed_value: int in [1505, 9_999_331]:
		var s: Scenario = T.camp(seed_value, self)
		var ann: MinerHandle = T.walk_up(s, "ann")
		s.step(200)
		var ops: Array[String] = []
		for d: Dictionary in T.ops_of(ann):
			ops.append(var_to_str(d))
		streams.append("\n".join(ops))
		assert_eq(ann.connection.sheet.sheet.count(), 0, "a blank sheet")
		assert_eq(s.run.sheets.table.sheet.count(), 0)
	assert_eq(streams[0], streams[1], "the same stream whatever the seed")
	assert_eq(streams[0], "\n".join([var_to_str({"op": SheetCodec.Op.RESET}), var_to_str({"op": SheetCodec.Op.FULL, "on": false})]),
		"a reset and 'not full', nothing else")
