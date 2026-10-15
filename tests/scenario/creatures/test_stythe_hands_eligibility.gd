extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-13 (§13.9): a Hired Hand is never taken while an unlit human is within the Stythe's sensing
## range; once none is, a Hand in its reach or sensed in its territory is eligible, never by the
## unheard mark or the Pull.

const W = preload("res://tests/unit/creatures/stythe_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_each() -> void:
	WorldCoords.ring_override = -1


func test_hands_only_when_no_unlit_human_is_sensed() -> void:
	WorldCoords.ring_override = 1
	var s: Scenario = make({"seed": 1281, "fixture": W.road(80), "overrides": W.ON})
	var st: StytheCreature = W.stythe(s, Vector2i(30, 2))
	var hand: MinerHandle = W.miner(s, "hand", Vector2i(31, 2))
	var ann: MinerHandle = W.miner(s, "ann", Vector2i(37, 2))
	var far_hand: MinerHandle = W.miner(s, "far_hand", Vector2i(70, 2))
	var hands: Array[int] = [hand.entity_id, far_hand.entity_id]
	s.run.crew.is_hand_driven = func(e: int) -> bool: return hands.has(e)
	s.step(2)
	assert_true(st.senses.senses(ann.entity_id), "Ann, unlit, 7 tiles off")
	assert_eq(StytheEligibility.row(s.run, st, hand.entity_id), "", "the Hand in reach is not taken while she is sensed")
	assert_ne(st.best_target(s.run), hand.entity_id)
	W.light(s, Vector2i(37, 2), 0.5)
	s.step(2)
	assert_eq(StytheEligibility.row(s.run, st, hand.entity_id), "reach", "Ann lit: the Hand in reach")
	W.pull(st, {far_hand.entity_id: 90.0})
	s.step(2)
	assert_eq(StytheEligibility.row(s.run, st, far_hand.entity_id), "", "a Hand never by the Pull")
