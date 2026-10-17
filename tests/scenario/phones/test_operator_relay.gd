extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-13 (Gameplay §4.10's relay): Ann's line calls; the operator plugs in and hears her; the operator
## stands up to draw, leaving her held in hiss, and Dee's call buzzes unanswered meanwhile; sits again
## and takes Ann's line back; then rings Cat's line, whose bell sounds at her phone. Cat answers at
## the wall, and the cord goes to her line, Ann's call held: one line at a time, two teams talking
## only through the operator, and Dee's flap still down.

const W = preload("res://tests/unit/phones/board_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


static func _calls_heard(h: MinerHandle) -> int:
	var n: int = 0
	for raw: Array in h.connection.voice_in:
		var packet: PackedByteArray = raw[0]
		if Variants.flag(VoicePackets.read_down(packet).get("telephone", false)):
			n += 1
	h.connection.voice_in.clear()
	return n


func test_the_operators_relay() -> void:
	var s: Scenario = make(W.cfg(5501))
	W.camp(s)
	s.run.power.switch_closed = true
	var first: Array = W.phone_and_caller(s, "a", 0, "ann")
	var second: Array = W.phone_and_caller(s, "b", 6, "cat")
	var third: Array = W.phone_and_caller(s, "c", 9, "dee")
	var a: PitPhone = first[0]
	var ann: MinerHandle = first[1]
	var b: PitPhone = second[0]
	var cat: MinerHandle = second[1]
	var c: PitPhone = third[0]
	var dee: MinerHandle = third[1]
	var op: MinerHandle = W.operator(s, "bob", 12)
	W.crank(s, ann)
	var shown: PackedByteArray = op.connection.board.get("flaps", PackedByteArray())
	assert_eq(shown[a.number - 1], BoardWire.Flap.DOWN, "line %d's flap down on the operator's board" % a.number)
	W.ask(s, op, BoardWire.Verb.PLUG, a.number)
	op.connection.voice_in.clear()
	ann.at(s.run.tick).say(1, 4)
	s.step(8)
	assert_eq(_calls_heard(op), 4, "the operator hears her")
	# The operator stands: her call held, in hiss.
	op.at(s.run.tick).press(ActionRecord.Kind.CLOSE_UP, CloseupKind.Ask.CLOSE)
	s.step(50)
	assert_eq(s.run.closeups.operator(), 0, "stood up")
	assert_eq(a.state, PitPhone.State.HELD, "her call held")
	assert_ne(int(Variants.number(OwnStatus.of(s.run, ann.entity_id)["flags"])) & StatusWire.LINE_HISS, 0, "she hears hiss")
	# While the operator draws, Dee's call buzzes unanswered.
	var repeat: int = roundi(Tuning.f(&"phones.buzzer_repeat_s") * Tuning.f(&"net.tick_hz"))
	var buzzes: int = W.events_of(s, NoiseTypes.Type.BUZZER).size()
	W.crank(s, dee)
	s.step(repeat * 2)
	assert_eq(W.events_of(s, NoiseTypes.Type.BUZZER).size(), buzzes + 3, "calls buzz while the operator draws")
	assert_eq(c.state, PitPhone.State.CALLING, "and nothing answers")
	# Sits again, takes Ann's line back.
	W.seat(s, op)
	W.ask(s, op, BoardWire.Verb.PLUG, a.number)
	assert_eq(a.state, PitPhone.State.ON_CALL, "back with Ann")
	# Rings Cat's line: the bell at her phone; she answers; the cord goes to her line, Ann held.
	W.ask(s, op, BoardWire.Verb.RING, b.number)
	var bells: Array[NoiseSystem.Event] = W.events_of(s, NoiseTypes.Type.PHONE_BELL)
	assert_eq(bells.size(), 1, "the bell")
	assert_true(bells[0].origins.has(b.tile), "at Cat's phone")
	W.P.press(s, cat)
	assert_eq(b.state, PitPhone.State.ON_CALL, "Cat answers")
	assert_eq(s.run.switchboard.cord, b.number, "the cord in her line")
	assert_eq(a.state, PitPhone.State.HELD, "Ann held: one line at a time")
	for h: MinerHandle in [ann, cat, dee, op]:
		h.connection.voice_in.clear()
	cat.at(s.run.tick).say(1, 4)
	s.step(8)
	assert_eq(_calls_heard(op), 4, "Cat reaches the operator")
	assert_eq(_calls_heard(ann), 0, "never Ann")
	assert_eq(_calls_heard(dee), 0, "nor Dee")
	assert_eq(W.flaps(s)[c.number - 1], BoardWire.Flap.DOWN, "Dee's flap still down")
	assert_eq(W.flaps(s)[a.number - 1], BoardWire.Flap.HELD, "Ann's held")
