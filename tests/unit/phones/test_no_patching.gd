extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-13 (Gameplay §6.6, §4.10): the board never patches two lines. With one caller held and one
## connected, no frame passes between the two phones: each caller talks to the operator alone, the
## held one to nobody, and two teams hear each other only through the operator's mouth.

const W = preload("res://tests/unit/phones/board_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


static func _from(h: MinerHandle) -> int:
	var n: int = 0
	for raw: Array in h.connection.voice_in:
		var packet: PackedByteArray = raw[0]
		var d: Dictionary = VoicePackets.read_down(packet)
		if Variants.flag(d.get("telephone", false)):
			n += 1
	h.connection.voice_in.clear()
	return n


func test_one_held_one_connected_nothing_between_them() -> void:
	var s: Scenario = make(W.cfg(5401))
	W.camp(s)
	s.run.power.switch_closed = true
	var first: Array = W.phone_and_caller(s, "p1", 0, "ann")
	var second: Array = W.phone_and_caller(s, "p2", 6, "cat")
	var p1: PitPhone = first[0]
	var ann: MinerHandle = first[1]
	var p2: PitPhone = second[0]
	var cat: MinerHandle = second[1]
	var op: MinerHandle = W.operator(s, "bob", 12)
	W.crank(s, ann)
	W.ask(s, op, BoardWire.Verb.PLUG, p1.number)
	W.crank(s, cat)
	W.ask(s, op, BoardWire.Verb.PLUG, p2.number)
	assert_eq(p1.state, PitPhone.State.HELD, "Ann held")
	assert_eq(p2.state, PitPhone.State.ON_CALL, "Cat connected")
	for h: MinerHandle in [ann, cat, op]:
		h.connection.voice_in.clear()
	ann.at(s.run.tick).say(1, 5)
	s.step(8)
	assert_eq(_from(cat), 0, "nothing of Ann reaches Cat")
	assert_eq(_from(op), 0, "nor the operator: she is held")
	cat.at(s.run.tick).say(1, 5)
	s.step(8)
	assert_eq(_from(op), 5, "Cat reaches the operator")
	assert_eq(_from(ann), 0, "and never Ann")
	op.at(s.run.tick).say(1, 5)
	s.step(8)
	assert_eq(_from(cat), 5, "the operator reaches Cat")
	assert_eq(_from(ann), 0, "and not the held line")
	assert_false(Variants.dict(s.run.voice.direct.get(ann.slot, {})).has(cat.slot), "no line joins the two phones")
	assert_false(Variants.dict(s.run.voice.direct.get(cat.slot, {})).has(ann.slot))
