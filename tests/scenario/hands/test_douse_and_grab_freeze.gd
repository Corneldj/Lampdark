extends "res://tests/scenario/kit/scenario_test.gd"
## MOD-08 (Gameplay §13.9): a human grabbed within 12 tiles by path shutters a Hand's lamp and
## freezes it until the grab ends; it then follows again (its lamp stays shuttered until 'Light up!').
## A grab beyond 12 tiles by path, even one straight across rock, freezes nothing. A Hand's light
## never breaks a grab.

const HW = preload("res://tests/unit/hands/hand_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_grab_nearby_shutters_and_freezes_a_hand() -> void:
	var s: Scenario = make({"seed": 4861, "fixture": HW.road(50)})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = HW.human(s, "ann", a + Vector2i(12, 0), 0.0)
	var bob: MinerHandle = HW.human(s, "bob", a + Vector2i(16, 0), 180.0)
	var hand: int = HW.hand(s, a + Vector2i(4, 0), 4, true)
	s.step(40)
	assert_false(HW.lamp_of(s, hand).shutter_closed)
	var g: int = s.run.holds.grab(s.run, bob.entity_id, GrabHold.Kind.TAPPER_PIN, 0, 2000)
	assert_gte(g, 0)
	s.step(20)
	assert_true(HW.h_of(s, hand).grab_frozen, "Bob is grabbed within 12 tiles by path")
	assert_true(HW.lamp_of(s, hand).shutter_closed, "its lamp shuttered")
	var at: Vector2 = HW.pos(s, hand)
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.WALK, 40)
	s.step(60)
	assert_lt(HW.pos(s, hand).distance_to(at), 0.05, "frozen while the grab lasts, its human walking off")
	assert_true(s.run.holds.end_grab(s.run, g, GrabHold.Outcome.BROKEN))
	s.step(80)
	assert_false(HW.h_of(s, hand).grab_frozen, "the grab over")
	assert_gt(HW.pos(s, hand).x, at.x + 1.0, "it follows again")
	assert_true(HW.lamp_of(s, hand).shutter_closed, "dark until 'Light up!'")


func test_a_grab_beyond_twelve_tiles_by_path_freezes_nothing() -> void:
	var s: Scenario = make({"seed": 4862, "fixture": HW.road(50)})
	var a: Vector2i = s.fixture.spot("a")
	HW.human(s, "ann", a, 0.0)
	var bob: MinerHandle = HW.human(s, "bob", a + Vector2i(30, 0), 180.0)
	var hand: int = HW.hand(s, a + Vector2i(4, 0), 4, true)
	s.step(40)
	assert_gte(s.run.holds.grab(s.run, bob.entity_id, GrabHold.Kind.TAPPER_PIN, 0, 2000), 0)
	s.step(20)
	assert_false(HW.h_of(s, hand).grab_frozen, "26 tiles by path: no freeze")
	assert_false(HW.lamp_of(s, hand).shutter_closed)
