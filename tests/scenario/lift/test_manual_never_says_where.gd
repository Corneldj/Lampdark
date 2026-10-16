extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-03 (Gameplay §3.3, §14.3): the Manual at its lectern prints exactly the run's jobs, in the
## Company's order, with the can count and the kind of place a part is kept, and never ticks itself.
## A client is sent only the list's kind, can count and jobs, the first time its miner opens the
## Manual: never the seed, the plan, a location, a distance, a band, a spare or a done flag. The
## crew's pencil over it is a sheet of its own, under the map table's rules.

const W = preload("res://tests/scenario/ui/closeup_world.gd")
const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _manual_messages(h: MinerHandle) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	for m: Dictionary in h.capture.messages:
		if int(Variants.number(m["type"])) == Protocol.Msg.MANUAL:
			var bytes: PackedByteArray = m["bytes"]
			var payload: PackedByteArray = Protocol.unframe(bytes)["payload"]
			out.append(payload)
	return out


func test_the_manual_is_sent_the_list_alone_and_prints_it_in_order() -> void:
	var s: Scenario = W.camp(2501, self)
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var ann: MinerHandle = W.beside(s, "ann", CloseupKind.Kind.MANUAL)
	s.step(10)
	assert_eq(_manual_messages(ann).size(), 0, "nothing before the Manual is opened")
	var list: RepairList = s.run.repair.list
	# Some work done already: no done flag ever reaches the Manual.
	s.run.repair.mark_done(s.run, &"power")
	W.interact(s, ann)
	s.step(6)
	assert_eq(W.kind_of(s, ann), CloseupKind.Kind.MANUAL, "Ann reads the Manual")
	var sent: Array[PackedByteArray] = _manual_messages(ann)
	assert_eq(sent.size(), 1, "sent once")
	assert_eq(sent[0], RepairJobs.encode(list.kind, list.cans_required, list.jobs), "the kind, the cans and the jobs, nothing else")
	assert_eq(sent[0].size(), 2 + list.jobs.size(), "a byte for the kind, one for the cans, one a job")
	var got_jobs: Array[StringName] = ann.connection.manual["jobs"]
	assert_eq(got_jobs, list.jobs)
	W.ask(s, ann, CloseupKind.Ask.CLOSE)
	s.step(5)
	W.interact(s, ann)
	s.step(6)
	assert_eq(_manual_messages(ann).size(), 1, "the client keeps it: not sent again")
	assert_eq(audit.violation_count, 0, "NET-08's audit: the list only to a reader of the Manual, exactly")
	# The page prints exactly those jobs, numbered in the Company's order, the cans counted.
	var page: ManualCloseup = ManualCloseup.new()
	page.manual_list = func() -> Dictionary: return ann.connection.manual
	add_child_autofree(page)
	page.set_anchors_preset(Control.PRESET_TOP_LEFT)
	page.size = Vector2(1280, 800)
	var text: String = ""
	for line: Dictionary in page.printed_lines():
		text += str(line["text"]) + " "
	var at: int = -1
	for i: int in list.jobs.size():
		var head: String = "%d. %s" % [i + 1, UiText.text("manual.job.%s.name" % list.jobs[i])]
		var found: int = text.find(head)
		assert_gt(found, at, "%s printed, in order" % head)
		at = found
	assert_true(text.contains(UiText.text("manual.cans.%d" % list.cans_required)), "the cans counted")
	for job: StringName in RepairJobs.COMPANY_ORDER:
		if not list.jobs.has(job):
			assert_false(text.contains(UiText.text("manual.job.%s.name" % job)), "%s is not this run's" % job)
	assert_eq(ann.connection.sheet_of(SheetKind.Kind.MANUAL).sheet.count(), 0, "it never ticks itself")


func test_the_crews_pencil_on_the_manual_is_a_sheet_of_its_own() -> void:
	var s: Scenario = W.camp(2502, self)
	var ann: MinerHandle = W.beside(s, "ann", CloseupKind.Kind.MANUAL)
	var bob: MinerHandle = W.beside(s, "bob", CloseupKind.Kind.MANUAL, 1)
	s.step(5)
	s.run.closeups.open_for(s.run, ann.entity_id, CloseupKind.Kind.MANUAL, "test")
	s.run.closeups.open_for(s.run, bob.entity_id, CloseupKind.Kind.MANUAL, "test")
	s.step(2)
	var tick: PackedVector2Array = PackedVector2Array([Vector2(-900, -1100), Vector2(-880, -1080), Vector2(-850, -1130)])
	ann.connection.sheet_of(SheetKind.Kind.MANUAL).commit_stroke(tick, Transport.now_usec())
	ann.connection.sheet_of(SheetKind.Kind.MANUAL).commit_label(Vector2(500, -1100), "fuses: east cabin?", Transport.now_usec())
	s.step(20)
	var manual: MapTable = s.run.sheets.sheets[SheetKind.Kind.MANUAL]
	assert_eq(manual.sheet.count(), 2, "the tick and the margin note on the Manual")
	assert_eq(s.run.sheets.table.sheet.count(), 0, "nothing on the map table")
	assert_eq(bob.connection.sheet_of(SheetKind.Kind.MANUAL).sheet.count(), 2, "Bob, at the Manual too, holds them")
	assert_eq(bob.connection.sheet.sheet.count(), 0, "and his map table copy is untouched")
	# Drawing on the Manual's sheet from the map table's close-up is refused, as anywhere off it.
	s.run.closeups.close(bob.entity_id, "test")
	s.run.closeups.open_for(s.run, bob.entity_id, CloseupKind.Kind.MAP_TABLE, "test")
	bob.connection.sheet_of(SheetKind.Kind.MANUAL).commit_stroke(tick, Transport.now_usec())
	s.step(10)
	assert_eq(manual.sheet.count(), 2, "not at the Manual: nothing")
	assert_true(Variants.array(s.run.sheets.refused.map(func(r: Dictionary) -> String: return str(r["why"]))).has("not at the table"))
