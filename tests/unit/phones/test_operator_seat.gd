extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-13 with UI-02 (Gameplay §4.10, §13.9, §13.11; A.6): the operator's seat. Sitting takes 2 s,
## and so does standing; one operator at a time; a Hired Hand never sits. A fall, a grab or a drop
## unseats at once, and the call the operator was on is held, its caller waiting in hiss. A line the
## operator rang, answered after they left, reaches the board as a call: never onto the miner who rang.

const W = preload("res://tests/unit/phones/board_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _seat_tile(s: Scenario) -> Vector2i:
	var seats: Array[Dictionary] = Basecamp.fixture(s.run.base_camp.seed_value, "switchboard_seat", s.run.base_camp.side)
	return seats[0]["position"]


func _opened_at(s: Scenario, entity: int) -> int:
	for h: Dictionary in s.run.closeups.history:
		if int(Variants.number(h["entity"])) == entity and Variants.flag(h["open"]):
			return int(Variants.number(h["tick"]))
	return -1


func _closed_at(s: Scenario, entity: int) -> int:
	var at: int = -1
	for h: Dictionary in s.run.closeups.history:
		if int(Variants.number(h["entity"])) == entity and not Variants.flag(h["open"]):
			at = int(Variants.number(h["tick"]))
	return at


func test_two_seconds_to_sit_and_to_stand_one_at_a_time_never_a_hand() -> void:
	var s: Scenario = make(W.cfg(5301))
	W.camp(s)
	var seat: Vector2i = _seat_tile(s)
	var ann: MinerHandle = s.add_miner("ann", seat)
	ann.brain = null
	s.step(2)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 60)
	var started: int = -1
	for _i: int in 20:
		s.step()
		var a: TimedAction = s.run.inventory.actions.get(ann.entity_id, null)
		if a != null and a.verb == &"sit_at_board":
			started = a.started_tick
			break
	assert_gt(started, 0, "she sits down")
	s.step(50)
	assert_eq(s.run.closeups.operator(), ann.entity_id, "the operator")
	assert_eq(_opened_at(s, ann.entity_id) - started + 1, 40, "in 2 s: 40 ticks held, the first the tick it began")
	# Bob cannot take the seat while she has it, nor could a Hand.
	var bob: MinerHandle = s.add_miner("bob", seat + Vector2i(0, 1))
	bob.brain = null
	s.step(2)
	s.run.movement.place(s.run, bob.entity_id, Vector2(seat) + Vector2(0.5, 0.9))
	bob.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 60)
	s.step(60)
	assert_eq(s.run.closeups.operator(), ann.entity_id, "one operator at a time")
	# She stands: 2 s.
	ann.at(s.run.tick).press(ActionRecord.Kind.CLOSE_UP, CloseupKind.Ask.CLOSE)
	var asked: int = s.run.tick
	s.step(60)
	assert_eq(s.run.closeups.operator(), 0, "she stood up")
	assert_between(_closed_at(s, ann.entity_id) - asked, 40, 46, "in 2 s (and the input's way up)")
	# Now a Hand at the seat never sits.
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == bob.entity_id
	s.step(10)
	bob.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 60)
	s.step(60)
	assert_eq(s.run.closeups.operator(), 0, "a Hired Hand never sits")


func test_a_fall_a_grab_or_a_drop_unseats_at_once_and_the_call_is_held() -> void:
	var s: Scenario = make(W.cfg(5302))
	W.camp(s)
	s.run.power.switch_closed = true
	var pc: Array = W.phone_and_caller(s, "p1", 0, "ann")
	var p: PitPhone = pc[0]
	var ann: MinerHandle = pc[1]
	var op: MinerHandle = W.operator(s, "bob", 8)
	W.crank(s, ann)
	W.ask(s, op, BoardWire.Verb.PLUG, p.number)
	assert_eq(p.state, PitPhone.State.ON_CALL)
	assert_true(s.run.falls.fall_unconscious(s.run, op.entity_id, FallCause.Cause.BLAST))
	s.step(1)
	assert_eq(s.run.closeups.operator(), 0, "fallen: unseated at once")
	s.step(1)
	assert_eq(p.state, PitPhone.State.HELD, "the call held")
	assert_ne(int(Variants.number(OwnStatus.of(s.run, ann.entity_id)["flags"])) & StatusWire.LINE_HISS, 0, "its caller in hiss")
	# Another operator, then grabbed.
	var dee: MinerHandle = W.operator(s, "dee", 15)
	W.ask(s, dee, BoardWire.Verb.PLUG, p.number)
	assert_eq(p.state, PitPhone.State.ON_CALL, "on the line again")
	s.run.miner_state.enter_grabbed(dee.entity_id, &"drag", 0)
	s.step(1)
	assert_eq(s.run.closeups.operator(), 0, "grabbed: unseated at once")
	s.step(1)
	assert_eq(p.state, PitPhone.State.HELD, "the call held")
	# Another operator, then dropped.
	var cat: MinerHandle = W.operator(s, "cat", 12)
	W.ask(s, cat, BoardWire.Verb.PLUG, p.number)
	assert_eq(p.state, PitPhone.State.ON_CALL, "back on the line")
	cat.at(s.run.tick).disconnect_at()
	assert_true(s.run_until(func(sc: Scenario) -> bool: return not sc.run.drops.drops.is_empty(), 200), "dropped")
	s.step(2)
	assert_eq(s.run.closeups.operator(), 0, "a dropped operator stands up")
	assert_eq(p.state, PitPhone.State.HELD, "and the call is held")


func test_a_line_rung_then_left_answers_to_the_board() -> void:
	var s: Scenario = make(W.cfg(5303))
	W.camp(s)
	s.run.power.switch_closed = true
	var pc: Array = W.phone_and_caller(s, "p1", 0, "ann")
	var p: PitPhone = pc[0]
	var ann: MinerHandle = pc[1]
	var op: MinerHandle = W.operator(s, "bob", 8)
	W.ask(s, op, BoardWire.Verb.RING, p.number)
	assert_eq(W.events_of(s, NoiseTypes.Type.PHONE_BELL).size(), 1, "her bell")
	assert_true(s.run.falls.fall_unconscious(s.run, op.entity_id, FallCause.Cause.BLAST))
	s.step(2)
	assert_eq(s.run.closeups.operator(), 0, "whoever rang is gone from the board")
	W.P.press(s, ann)
	assert_eq(p.state, PitPhone.State.CALLING, "her answer waits at the board, a call")
	assert_eq(p.caller, ann.entity_id)
	assert_false(Variants.dict(s.run.voice.direct.get(ann.slot, {})).has(op.slot), "never a line to the miner who rang")
	assert_eq(W.flaps(s)[p.number - 1], BoardWire.Flap.DOWN, "her flap down")
	assert_eq(W.events_of(s, NoiseTypes.Type.BUZZER).size(), 1, "the buzzer")
	var cat: MinerHandle = W.operator(s, "cat", 12)
	W.ask(s, cat, BoardWire.Verb.PLUG, p.number)
	assert_eq(p.state, PitPhone.State.ON_CALL, "the next operator answers it")
	assert_true(Variants.dict(s.run.voice.direct.get(ann.slot, {})).has(cat.slot))
