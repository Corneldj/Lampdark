extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-04: a fallen player watching a teammate who then falls sees that fall play out 45 s late, up to
## the fall and its tail, and then the screen goes dark: the watch ends and no later frame of the
## teammate arrives. The client's DarkView stops drawing the stream. NET-08's audit passes throughout.

const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")
const D = preload("res://tests/scenario/rescue/dark_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_watched_fall_plays_out_then_goes_dark() -> void:
	var s: Scenario = make({"seed": 551, "fixture": "test"})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var miners: Array[MinerHandle] = D.W.crew(s, 3, 551)
	var ann: MinerHandle = miners[0]
	var bob: MinerHandle = miners[1]
	ann.brain = null
	s.step(5)
	D.fall(s, ann)
	ann.at(s.run.tick + 1).press(ActionRecord.Kind.WATCH, 1)
	s.step(5)
	assert_eq(D.fallen(s, ann).watching, bob.slot, "the next conscious teammate: Bob")
	s.step(300)
	D.fall(s, bob)
	var bob_fell: int = D.fallen(s, bob).fell_tick
	var tail: int = roundi(Tuning.f(&"net.record_tail_s") * Tuning.f(&"net.tick_hz"))
	var delay: int = roundi(Tuning.f(&"rescue.watch_delay_s") * Tuning.f(&"net.tick_hz"))
	var view: DarkView = DarkView.new()
	s.step(bob_fell + delay - s.run.tick - 20)
	view.tick(ann.connection, 0.5)
	assert_true(view.watching, "still watching Bob, 45 s behind")
	assert_not_null(view.override_view(), "his stream drawn instead of her black")
	s.step(tail + 60)
	var last: int = -1
	var ended_at: int = -1
	var after_end: int = 0
	for m: Dictionary in ann.capture.messages:
		if int(Variants.number(m["type"])) != Protocol.Msg.WATCH:
			continue
		var bytes: PackedByteArray = m["bytes"]
		var payload: PackedByteArray = Protocol.unframe(bytes)["payload"]
		var d: Dictionary = DarkMessages.decode(payload)
		if Variants.flag(d["ended"]):
			ended_at = int(Variants.number(m["tick"]))
			continue
		for raw: Variant in Variants.array(d["frames"]):
			var fr: Array = raw
			var t: int = fr[0]
			last = maxi(last, t)
			if ended_at >= 0:
				after_end += 1
	gut.p("Bob fell at %d; last frame relayed %d; the watch ended at tick %d" % [bob_fell, last, ended_at])
	assert_gt(last, bob_fell, "his fall played out")
	assert_lte(last, bob_fell + tail, "up to the fall and its tail, no later")
	assert_gte(ended_at, bob_fell + delay, "late, like the rest of it")
	assert_eq(after_end, 0, "nothing after the end")
	assert_eq(D.fallen(s, ann).watching, -1, "the watch is over")
	view.tick(ann.connection, 5.0)
	assert_false(view.watching, "the client stops drawing his stream")
	assert_null(view.override_view(), "and her screen is black again")
	assert_eq(view.mode(s.client(ann).records_at(s.run.tick - 1)), WorldView.Mode.BLACK)
	assert_false(s.run.dark.watchable(s.run, ann.slot).has(bob.slot), "a fallen teammate is not offered")
	for v: Dictionary in audit.violations.slice(0, 12):
		gut.p("VIOLATION %s" % v)
	assert_eq(audit.violation_count, 0, "no audit violation")
	assert_gt(int(Variants.number(Variants.dict(audit.report()["checked"]).get("watch", 0))), 0, "watch records were judged")
