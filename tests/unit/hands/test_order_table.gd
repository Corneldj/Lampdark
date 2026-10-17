extends "res://tests/scenario/kit/scenario_test.gd"
## MOD-08 (Gameplay §13.9): the order table, row by row. 'Douse!' shutters the Hand's lamp and
## freezes it while its human stands still; 'Light up!' opens it, relighting by flint when it is
## Out; 'Quiet!' crouches it until the next order; STOP stands it, COME walks it to the signaller,
## OK resumes following. Anything else (a whisper it does not keep, a shouted line that is no order,
## a rock tap) changes nothing. (Following: test_follow_switching; 'Count off!':
## test_count_off_answer; POINT: test_point_jobs; a grab: test_douse_and_grab_freeze.)

const HW = preload("res://tests/unit/hands/hand_world.gd")
const W = preload("res://tests/unit/sound/signal_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_the_table_maps_callouts_and_signals() -> void:
	assert_eq(HandOrders.of_callout("douse"), HandOrders.Order.DOUSE)
	assert_eq(HandOrders.of_callout("light_up"), HandOrders.Order.LIGHT_UP)
	assert_eq(HandOrders.of_callout("quiet"), HandOrders.Order.QUIET)
	assert_eq(HandOrders.of_callout("count_off"), HandOrders.Order.COUNT_OFF)
	for line: String in ["here", "help", "is_that_you", "gate", "oil", "moth", "tapping", "stythe", "now", "right", "stop", "left"]:
		assert_eq(HandOrders.of_callout(line), HandOrders.Order.NONE, "'%s' is no order" % line)
	assert_eq(HandOrders.of_signal(LampSignalKind.Kind.STOP), HandOrders.Order.STOP)
	assert_eq(HandOrders.of_signal(LampSignalKind.Kind.COME), HandOrders.Order.COME)
	assert_eq(HandOrders.of_signal(LampSignalKind.Kind.OK), HandOrders.Order.OK)
	assert_eq(HandOrders.of_signal(LampSignalKind.Kind.POINT), HandOrders.Order.POINT)
	assert_eq(HandOrders.of_signal(LampSignalKind.Kind.HELP), HandOrders.Order.NONE, "HELP is for the crew")


func test_douse_shutters_and_freezes_while_its_human_stands() -> void:
	var s: Scenario = make({"seed": 4801, "fixture": HW.road(40)})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = HW.human(s, "ann", a, 0.0)
	var hand: int = HW.hand(s, a + Vector2i(4, 0), 4, true)
	s.step(20)
	assert_false(HW.lamp_of(s, hand).shutter_closed)
	ann.at(s.run.tick).callout("douse", CalloutLines.TALK)
	s.step(20)
	assert_true(HW.lamp_of(s, hand).shutter_closed, "'Douse!': its lamp shuttered")
	var at: Vector2 = HW.pos(s, hand)
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.WALK, 1).wait(1)
	s.step(60)
	assert_lt(HW.pos(s, hand).distance_to(at), 0.05, "frozen while its human stands still")
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.WALK, 80)
	s.step(100)
	assert_gt(HW.pos(s, hand).x, at.x + 2.0, "it follows when its human moves on")
	assert_true(HW.lamp_of(s, hand).shutter_closed, "still dark until 'Light up!'")


func test_light_up_opens_and_relights_by_flint() -> void:
	var s: Scenario = make({"seed": 4802, "fixture": HW.road(40)})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = HW.human(s, "ann", a, 0.0)
	var hand: int = HW.hand(s, a + Vector2i(4, 0), 4, true)
	s.step(5)
	ann.at(s.run.tick).callout("douse", CalloutLines.TALK)
	s.step(30)
	assert_true(HW.lamp_of(s, hand).shutter_closed)
	ann.at(s.run.tick).callout("light_up", CalloutLines.TALK)
	s.step(30)
	assert_false(HW.lamp_of(s, hand).shutter_closed, "'Light up!': open again")
	var l: GauzeLamp = HW.lamp_of(s, hand)
	assert_true(s.run.lamps.snuff(s.run, l, "test"))
	assert_false(l.burning())
	var relit_before: int = s.run.lamps.relights.size()
	ann.at(s.run.tick + 40).callout("light_up", CalloutLines.TALK)
	s.step(140)
	assert_true(l.burning(), "relit by flint")
	assert_gt(s.run.lamps.relights.size(), relit_before)
	assert_eq(str(s.run.lamps.relights[s.run.lamps.relights.size() - 1]["method"]), "flint")


func test_quiet_crouches_until_the_next_order() -> void:
	var s: Scenario = make({"seed": 4803, "fixture": HW.road(40)})
	var a: Vector2i = s.fixture.spot("a")
	var hand: int = HW.hand(s, a, 4, false)
	var ann: MinerHandle = HW.human(s, "ann", a + Vector2i(2, 0), 180.0)
	s.step(5)
	ann.at(s.run.tick).callout("quiet", CalloutLines.WHISPER)
	s.step(20)
	assert_true(HW.h_of(s, hand).crouched, "'Quiet!'")
	# Ann walks east out of the band: the Hand follows, crouching.
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.WALK, 60)
	var gaits: Dictionary = {}
	for _i: int in 100:
		s.step(1)
		gaits[s.run.movement.miner(4).state.gait] = true
	assert_true(gaits.has(MinerMotion.CROUCH), "it crouches as it follows")
	assert_false(gaits.has(MinerMotion.WALK), "never upright while 'Quiet!' holds")
	ann.at(s.run.tick).callout("count_off", CalloutLines.TALK)
	s.step(10)
	assert_false(HW.h_of(s, hand).crouched, "until the next order")


func test_stop_come_and_ok() -> void:
	var s: Scenario = make({"seed": 4804, "fixture": HW.road(40)})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = HW.human(s, "ann", a + Vector2i(10, 0), 180.0)
	var hand: int = HW.hand(s, a + Vector2i(14, 0), 4, false)
	s.run.movement.miner(4).state.facing = HandController.facing_u16(Vector2(-1, 0))
	s.step(10)
	W.signal_press(s, ann, LampSignalKind.Kind.STOP)
	s.step(10)
	assert_eq(HW.h_of(s, hand).state, HandController.State.STAND, "STOP: it stands")
	var stood: Vector2 = HW.pos(s, hand)
	ann.at(s.run.tick).move(180.0, InputRecord.Gait.WALK, 60).face(0.0)
	s.step(80)
	assert_lt(HW.pos(s, hand).distance_to(stood), 0.05, "and stays as its human walks off")
	W.signal_press(s, ann, LampSignalKind.Kind.COME)
	s.step(5)
	assert_eq(HW.h_of(s, hand).state, HandController.State.COME, "COME")
	s.step(200)
	assert_lte(HW.path_tiles(s, hand, ann.entity_id), Tuning.f(&"hands.follow_min_tiles") + 1.0, "it walked to the signaller")
	assert_eq(HW.h_of(s, hand).state, HandController.State.FOLLOW, "and follows again")
	W.signal_press(s, ann, LampSignalKind.Kind.STOP)
	s.step(10)
	W.signal_press(s, ann, LampSignalKind.Kind.OK)
	s.step(10)
	assert_eq(HW.h_of(s, hand).state, HandController.State.FOLLOW, "OK: it resumes following")


func test_anything_else_changes_nothing() -> void:
	var s: Scenario = make({"seed": 4805, "fixture": HW.road(50)})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = HW.human(s, "ann", a, 0.0)
	var hand: int = HW.hand(s, a + Vector2i(4, 0), 4, true)
	s.step(20)
	var h: HandController.Hand = HW.h_of(s, hand)
	var before: Array = [h.state, h.crouched, h.doused, HW.lamp_of(s, hand).shutter_closed]
	ann.at(s.run.tick).callout("moth", CalloutLines.SHOUT)  # a shouted line that is no order
	s.step(30)
	ann.at(s.run.tick).callout("help", CalloutLines.TALK)
	s.step(30)
	W.tap_press(s, ann)  # a rock tap
	s.step(30)
	ann.at(s.run.tick).say(CalloutLines.SHOUT, 20)  # a shout without a callout
	s.step(30)
	assert_eq(s.run.hands.orders_taken.size(), 0, "no order taken")
	assert_eq([h.state, h.crouched, h.doused, HW.lamp_of(s, hand).shutter_closed], before, "nothing changed")
	# An order too far to keep: the Hand never takes it.
	var far: int = HW.hand(s, a + Vector2i(46, 0), 3, true)
	ann.at(s.run.tick).callout("douse", CalloutLines.TALK)
	s.step(30)
	assert_false(HW.lamp_of(s, far).shutter_closed, "a call 46 tiles off is not kept")
	assert_true(HW.lamp_of(s, hand).shutter_closed, "the Hand beside her kept it")
