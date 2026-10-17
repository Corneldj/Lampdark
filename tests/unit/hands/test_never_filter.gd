extends "res://tests/scenario/kit/scenario_test.gd"
## MOD-08 (Gameplay §13.9): the never list. Whatever a Hand's input carries (an injected attempt),
## the filter lets through only movement, facing, gait and the lamp's state, the interact while a
## POINTed job works and the flint while it relights; everything else is stripped and counted, and
## a Hand sends no one-shot action at all. The world's systems refuse a Hand-driven miner too: the
## ring, the revolver's draw and the timed actions that need a held control never start for it.

const HW = preload("res://tests/unit/hands/hand_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_the_filter_keeps_only_what_a_hand_may_drive() -> void:
	var r: InputRecord = InputRecord.new()
	r.holds = 0xFFFF
	var refused: int = HandInteractionFilter.strip(r, HandInteractionFilter.allowed_for(false, false))
	assert_eq(r.holds, 0, "nothing held outside a job or a relight")
	assert_eq(refused, 0xFFFF)
	r.holds = 0xFFFF
	HandInteractionFilter.strip(r, HandInteractionFilter.allowed_for(true, false))
	assert_eq(r.holds, InputRecord.HOLD_INTERACT, "a working job: the interact alone")
	r.holds = 0xFFFF
	HandInteractionFilter.strip(r, HandInteractionFilter.allowed_for(false, true))
	assert_eq(r.holds, InputRecord.HOLD_RELIGHT, "a relight: the flint alone")


func test_injected_attempts_are_turned_away() -> void:
	var s: Scenario = make({"seed": 4831, "fixture": HW.road(30)})
	var a: Vector2i = s.fixture.spot("a")
	HW.human(s, "ann", a, 0.0)
	var hand: int = HW.hand(s, a + Vector2i(3, 0))
	var w: ItemWorld = s.run.inventory.world
	assert_true(s.run.inventory.give(s.run, hand, w.make(ItemKinds.Kind.REVOLVER)))
	assert_true(s.run.inventory.give(s.run, hand, w.make(ItemKinds.Kind.HEALING_KIT)))
	s.step(3)
	var every: Array[int] = [InputRecord.HOLD_INTERACT, InputRecord.HOLD_CHECK_LAMP, InputRecord.HOLD_AIM, InputRecord.HOLD_BREATH,
		InputRecord.HOLD_SQUINT, InputRecord.HOLD_FEEL, InputRecord.HOLD_SET_DOWN, InputRecord.HOLD_USE]
	var at_tick: Array[int] = [0]
	s.run.hands.inject = func(_run: RunState, e: int, r: InputRecord) -> Array[ActionRecord]:
		if e != hand:
			return [] as Array[ActionRecord]
		r.holds |= every[at_tick[0] % every.size()]
		at_tick[0] += 1
		var act: ActionRecord = ActionRecord.new()
		act.kind = ActionRecord.Kind.LAMP_SIGNAL
		return [act] as Array[ActionRecord]
	s.step(40 * every.size())
	s.run.hands.inject = Callable()
	assert_eq(s.run.hands.rejected_count, 40 * every.size(), "every attempt counted")
	assert_false(s.run.inventory.actions.has(hand), "no timed action started")
	var h: HandsAndBelt = s.run.inventory.hands_of(hand)
	assert_eq(h.count_of(ItemKinds.Kind.REVOLVER), 1, "the revolver never drawn or fired")
	assert_eq(h.count_of(ItemKinds.Kind.HEALING_KIT), 1, "the kit never used")
	assert_false(s.run.lamp_signals.active.has(hand), "no signal")
	var ann_entity: int = s.run.movement.miner(0).entity_id
	assert_false(s.run.ring.open(s.run, hand, ann_entity), "the ring refuses a Hand")
