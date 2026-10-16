extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-14 with UI-02's board (Gameplay §4.10): nobody draws seated. The operator in the board's
## close-up has no pencil: whatever their client sends is refused. Once they stand (2 s) and open
## the table they draw like anyone.

const T = preload("res://tests/scenario/sheets/table_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_seated_operator_cannot_draw_until_they_stand_and_go_to_the_table() -> void:
	var s: Scenario = T.camp(1602, self)
	var op: MinerHandle = T.W.beside(s, "op", CloseupKind.Kind.SWITCHBOARD)
	var hz: float = Tuning.f(&"net.tick_hz")
	T.W.interact(s, op, roundi((Tuning.f(&"phones.seat_s") + 0.5) * hz))
	s.step(roundi((Tuning.f(&"phones.seat_s") + 1.0) * hz))
	assert_eq(s.run.closeups.kind_of(op.entity_id), CloseupKind.Kind.SWITCHBOARD, "seated at the board")
	T.send_raw(op, SheetCodec.commit_stroke(1, T.line(Vector2.ZERO, Vector2(100, 0), 2)))
	op.connection.sheet.sketching(1, T.line(Vector2.ZERO, Vector2(100, 0), 2))
	s.step(3)
	assert_eq(T.refused_whys(s), ["seated"] as Array[String])
	assert_eq(s.run.sheets.table.sheet.count(), 0, "nothing on the sheet")
	assert_gt(s.run.sheets.sync.sketches_refused, 0, "nor any stroke as made")
	# The stand takes 2 s; then the table.
	T.W.ask(s, op, CloseupKind.Ask.CLOSE)
	s.step(roundi((Tuning.f(&"phones.seat_s") + 0.5) * hz))
	assert_eq(s.run.closeups.kind_of(op.entity_id), CloseupKind.Kind.NONE, "standing")
	T.open_table(s, op)
	T.send_raw(op, SheetCodec.commit_stroke(2, T.line(Vector2.ZERO, Vector2(100, 0), 2)))
	s.step(3)
	assert_eq(s.run.sheets.table.sheet.count(), 1, "at the table they draw")
