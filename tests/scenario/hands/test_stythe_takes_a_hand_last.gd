extends "res://tests/scenario/kit/scenario_test.gd"
## MOD-08 (Gameplay §7.4, §13.9): the Stythe takes a Hand only when no unlit human is within its
## senses. A real Hired Hand in its reach is never selected while Ann stands unlit 7 tiles off, tick
## after tick as it follows her; once she is lit, the Hand is taken by reach.

const S = preload("res://tests/unit/creatures/stythe_world.gd")
const HW = preload("res://tests/unit/hands/hand_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_each() -> void:
	super.after_each()
	WorldCoords.ring_override = -1


func test_never_a_hand_while_an_unlit_human_is_sensed() -> void:
	WorldCoords.ring_override = 1
	var s: Scenario = make({"seed": 4921, "fixture": S.road(80), "overrides": S.ON})
	var st: StytheCreature = S.stythe(s, Vector2i(30, 2))
	var hand: int = HW.hand(s, Vector2i(31, 2), 4)
	var ann: MinerHandle = S.miner(s, "ann", Vector2i(37, 2))
	s.step(2)
	assert_true(s.run.hands.is_hand(hand))
	assert_true(st.senses.senses(ann.entity_id), "Ann, unlit, sensed")
	for _i: int in 40:
		s.step(1)
		assert_ne(st.best_target(s.run), hand, "never the Hand while she is sensed")
	S.light(s, HW.pos(s, ann.entity_id).floor() as Vector2i, 0.5)
	s.step(2)
	if HW.pos(s, hand).distance_to(st.position(s.run)) <= Tuning.f(&"stythe.reach_tiles"):
		assert_eq(StytheEligibility.row(s.run, st, hand), "reach", "Ann lit: the Hand in reach may be taken")
