extends "res://tests/scenario/kit/scenario_test.gd"
## MOD-08 under NET-08's audit: a client sees a Hand as an ordinary miner, by its seen set, and
## nothing of a Hand's controller state, target or orders reaches any client stream. Hands follow,
## take orders, cough and work a POINTed job while every message sent is judged; none fails.

const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")
const HW = preload("res://tests/unit/hands/hand_world.gd")
const W = preload("res://tests/unit/sound/signal_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_nothing_of_a_hand_is_sent() -> void:
	var s: Scenario = make({"seed": 4931, "fixture": HW.road(50)})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = HW.human(s, "ann", a + Vector2i(8, 0), 0.0)
	var bob: MinerHandle = HW.human(s, "bob", a + Vector2i(30, 1), 180.0)
	var hand: int = HW.hand(s, a + Vector2i(2, 0), 4, true)
	HW.hand(s, a + Vector2i(40, 2), 3, true)
	var iw: ItemWorld = s.run.inventory.world
	s.step(20)
	var lit: Vector2i = s.run.lamp_signals.point_target(s.run, ann.entity_id, ann.slot)
	iw.put(s.run, iw.make(ItemKinds.Kind.PARAFFIN_CAN), Vector2(lit) + Vector2(0.5, 0.5))
	W.signal_press(s, ann, LampSignalKind.Kind.POINT)
	s.step(150)
	bob.at(s.run.tick).callout("count_off", CalloutLines.TALK)
	s.step(40)
	ann.at(s.run.tick).callout("douse", CalloutLines.TALK).wait(10).move(180.0, InputRecord.Gait.WALK, 60)
	s.step(120)
	assert_gt(s.run.hands.orders_taken.size(), 1, "the Hands took orders")
	var worker: HandController.Hand = s.run.hands.hands[hand]
	assert_true(CanCarry.holds_can(s.run, hand) or worker.state == HandController.State.JOB, "and a job")
	var r: Dictionary = audit.report()
	gut.p("judged: %s" % r["checked"])
	for v: Dictionary in audit.violations.slice(0, 8):
		gut.p("VIOLATION %s" % v)
	assert_eq(audit.violation_count, 0, "nothing sent that a client's miner could not perceive")
