extends "res://tests/scenario/kit/scenario_test.gd"
## MOD-08 (Gameplay §13.9, §3.6): Hands board the cage with their human (it rides only from the deck,
## LFT-10), never pull the cord (an injected pull is stripped, and the cord refuses a Hand), and never
## count toward its majority: Ann aboard alone rings the bell with one pull, and her Hand rides home.

const K = preload("res://tests/unit/lift/cage_world.gd")
const HW = preload("res://tests/unit/hands/hand_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_hand_boards_with_its_human_and_never_pulls() -> void:
	var s: Scenario = make({"seed": 4891, "fixture": K.E.T.C.scenario_fixture()})
	K.ready(s, 200.0)
	var home: Vector2i = s.run.base_camp.medbay_tables()[0]
	var hand: int = HW.hand(s, home, 4)
	var ann: MinerHandle = K.aboard(s, "ann", 0)
	s.step(2)
	HW.h_of(s, hand).followed = ann.entity_id
	var deck: Rect2i = s.run.cage.deck
	assert_true(s.run_until(func(sc: Scenario) -> bool: return SignalCord.aboard(sc.run, hand, deck), 600), "the Hand boards after her")
	assert_eq(SignalCord.required(s.run, deck), 1, "the Hand never counts toward the majority")
	# Every tick the Hand's input is made to hold the cord: the filter strips it.
	s.run.hands.inject = func(_run: RunState, e: int, r: InputRecord) -> Array[ActionRecord]:
		if e == hand:
			r.holds |= InputRecord.HOLD_INTERACT
		return [] as Array[ActionRecord]
	s.step(20)
	assert_false(s.run.cage.cord.pullers().has(hand), "a Hand never pulls the cord")
	assert_gt(s.run.hands.rejected_count, 0)
	s.run.hands.inject = Callable()
	var departed: Array[Dictionary] = []
	s.run.cage.cage_departed.connect(func(snap: Dictionary) -> void: departed.append(snap))
	K.pull(s, ann)
	assert_true(s.run_until(func(_sc: Scenario) -> bool: return not departed.is_empty(), K.bell_ticks() + 200), "one pull of one: the cage goes")
	var riders: Array = Variants.array(departed[0]["miners"])
	assert_true(riders.has(hand), "the Hand rides home with her")
	assert_true(riders.has(ann.entity_id))
