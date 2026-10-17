extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-13 (Gameplay §4.10, §6.2, §6.4, §3.2): the operator is a teammate both ways. A live call makes
## the caller and the operator heard by each other. The operator's voice is noise like anyone's:
## the line carries it to the caller, Cat beside the board hears it (base camp hears one side of
## every call), but beyond the shut gate no frame or record of it reaches Dee, and the rock there
## hears only its Road Graph event, 12 np down. Open, Dee hears the voice, and the event comes
## 12 np louder.

const W = preload("res://tests/unit/phones/board_world.gd")

const ROCK: int = 9101


func before_all() -> void:
	assert_true(Tuning.load_server())


static func _frames(h: MinerHandle, telephone: bool) -> int:
	var n: int = 0
	for raw: Array in h.connection.voice_in:
		var packet: PackedByteArray = raw[0]
		if Variants.flag(VoicePackets.read_down(packet).get("telephone", false)) == telephone:
			n += 1
	return n


static func _voice_records(h: MinerHandle) -> int:
	var n: int = 0
	for e: Dictionary in h.connection.events:
		if int(Variants.number(e["type"])) == NoiseTypes.Type.VOICE:
			n += 1
	return n


## The rock's delivery of `who`'s last voice event ({} if it heard nothing).
static func _rock_heard(s: Scenario, who: int) -> Dictionary:
	for i: int in range(s.run.noise.event_log.size() - 1, -1, -1):
		var e: NoiseSystem.Event = s.run.noise.event_log[i]
		if e.type != NoiseTypes.Type.VOICE or e.source_entity != who:
			continue
		for raw: Variant in e.deliveries:
			var d: Dictionary = Variants.dict(raw)
			if int(Variants.number(d["listener"])) == ROCK:
				return d
		return {}
	return {}


func _clear(miners: Array[MinerHandle]) -> void:
	for h: MinerHandle in miners:
		h.connection.voice_in.clear()


func test_both_ends_heard_and_the_operators_voice_stays_in_base_camp() -> void:
	var s: Scenario = make(W.cfg(5901))
	W.camp(s)
	W.C.shut_all(s, true)
	s.run.power.switch_closed = true
	var west: Gate = s.run.base_camp.gate_system.gate("west")
	var pc: Array = W.phone_and_caller(s, "p1", 0, "ann")
	var p: PitPhone = pc[0]
	var ann: MinerHandle = pc[1]
	var at_board: Vector2i = west.middle() - west.outward * 2
	var op: MinerHandle = s.add_miner("bob", at_board)
	op.brain = null
	W.seat(s, op)
	var cat: MinerHandle = s.add_miner("cat", at_board - west.outward * 2)
	cat.brain = null
	var road: Vector2i = west.middle() + west.outward * 3
	var dee: MinerHandle = s.add_miner("dee", road)
	dee.brain = null
	s.run.noise.set_creature_listener(ROCK, road, 1.0)
	s.step(2)
	W.crank(s, ann)
	W.ask(s, op, BoardWire.Verb.PLUG, p.number)
	assert_eq(p.state, PitPhone.State.ON_CALL, "on the line")
	var called: Array = []
	for e: Dictionary in s.run.heard.heard_log:
		if StringName(str(e["cause"])) == &"call":
			called.append(int(Variants.number(e["slot"])))
	assert_true(called.has(ann.slot), "the caller heard")
	assert_true(called.has(op.slot), "and the operator")
	# The operator screams at the board, the gate shut.
	var everyone: Array[MinerHandle] = [ann, cat, dee, op]
	_clear(everyone)
	var records: int = _voice_records(dee)
	op.at(s.run.tick).say(4, 4)
	s.step(8)
	assert_eq(_frames(ann, true), 4, "the line carries it to the caller")
	assert_gt(_frames(cat, false), 0, "Cat hears it in base camp")
	assert_eq(dee.connection.voice_in.size(), 0, "no frame of it beyond the shut gate")
	assert_eq(_voice_records(dee), records, "nor any record")
	var shut: Dictionary = _rock_heard(s, op.entity_id)
	assert_false(shut.is_empty(), "the rock beyond hears its event")
	if shut.is_empty():
		return
	assert_eq(int(Variants.number(shut["closed_portals"])), 1, "through the shut gate")
	# Open: Dee hears the voice; the event 12 np louder.
	s.run.mine.native.set_barrier(Vector2i.ZERO, west.barrier, true)
	s.step(2)
	_clear(everyone)
	op.at(s.run.tick).say(4, 4)
	s.step(8)
	assert_gt(_frames(dee, false), 0, "open: Dee hears the voice")
	var open: Dictionary = _rock_heard(s, op.entity_id)
	assert_false(open.is_empty())
	if open.is_empty():
		return
	assert_almost_eq(float(Variants.number(open["remaining_np"])) - float(Variants.number(shut["remaining_np"])),
		Tuning.f(&"noise.closed_portal_cost"), 0.01, "the shut gate took 12 np off it")
