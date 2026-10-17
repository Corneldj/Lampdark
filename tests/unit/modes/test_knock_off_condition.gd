extends "res://tests/scenario/kit/scenario_test.gd"
## MOD-05 (Gameplay §13.11, A.10): `knock_off_available` is true only while every conscious miner
## (players' miners, whoever drives them) is inside base camp and every gate is shut. It turns false
## the tick a gate opens or a conscious miner steps out; the unconscious and the dead anywhere never
## block it, nor does a filler Hand (Proposed). Public runs never knock off. Only the host asks, over
## its own server's link (no client message can).

const K = preload("res://tests/unit/modes/knock_off_world.gd")
const HW = preload("res://tests/unit/hands/hand_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_inside_with_every_gate_shut() -> void:
	K.S.clear(5001)
	var s: Scenario = make(K.cfg(5001))
	K.camp(s)
	var ann: MinerHandle = K.miner(s, "ann", 0)
	K.miner(s, "bob", 1)
	s.step(2)
	assert_true(s.run.knock_off.available, "every conscious miner inside, every gate shut")
	# A gate opens: false that tick.
	var gate: Gate = s.run.base_camp.gate_system.gates[0]
	K.C.shut_all(s, false)
	s.step(1)
	assert_false(s.run.knock_off.available, "a gate open")
	assert_ne(KnockOff.refusal(s.run), "")
	K.C.shut_all(s, true)
	s.step(2)
	assert_true(s.run.knock_off.available)
	# A conscious miner steps out: false that tick.
	var out: Vector2i = K.outside(s)
	assert_ne(out, Vector2i(-1, -1))
	s.run.movement.place(s.run, ann.entity_id, Vector2(out) + Vector2(0.5, 0.5))
	s.step(1)
	assert_false(s.run.knock_off.available, "Ann outside base camp")
	assert_eq(gate.side, gate.side)


func test_the_fallen_and_filler_hands_never_block_it() -> void:
	K.S.clear(5002)
	var s: Scenario = make(K.cfg(5002))
	K.camp(s)
	var ann: MinerHandle = K.miner(s, "ann", 0)
	var bob: MinerHandle = K.miner(s, "bob", 1)
	var cat: MinerHandle = K.miner(s, "cat", 2)
	var out: Vector2i = K.outside(s)
	s.run.movement.place(s.run, bob.entity_id, Vector2(out) + Vector2(0.5, 0.5))
	s.step(1)
	assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.ROOF_FALL))
	s.run.movement.place(s.run, cat.entity_id, Vector2(out) + Vector2(1.5, 0.5))
	s.run.miner_state.kill(cat.entity_id, "test")
	HW.hand(s, out + Vector2i(0, 1), 4)
	s.step(2)
	assert_true(s.run.knock_off.available, "Bob unconscious and Cat dead outside, a filler Hand outside: no block")
	# A Hand driving a player's miner is a conscious miner: it blocks.
	var w: Array[int] = [ann.entity_id]
	s.run.movement.place(s.run, ann.entity_id, Vector2(out) + Vector2(2.5, 0.5))
	ann.at(s.run.tick).disconnect_at()
	assert_true(s.run_until(func(sc: Scenario) -> bool: return sc.run.hands.is_hand_driven(w[0]), 200))
	s.step(1)
	assert_false(s.run.knock_off.available, "a dropped player's miner outside blocks it, whoever drives it")


func test_never_in_public() -> void:
	K.S.clear(5003)
	var s: Scenario = make(K.cfg(5003, ServerConfig.Mode.PUBLIC))
	K.camp(s)
	K.miner(s, "ann", 0)
	s.step(2)
	assert_false(s.run.knock_off.available)
	assert_eq(KnockOff.refusal(s.run), "A public run is never saved.")
	assert_ne(K.knock_off(s), "", "refused")
	assert_false(s.run.frozen)
	assert_eq(s.run.saves.written.size(), 0, "nothing saved")


func test_only_the_host_asks() -> void:
	for name: String in Protocol.Msg.keys():
		assert_false(name.contains("KNOCK_OFF"), "no client message asks for a knock-off (%s)" % name)
	var src: String = FileAccess.get_file_as_string("res://server/server_main.gd")
	assert_true(src.contains("host_link.knock_off_requested.connect(_on_knock_off_requested)"), "the host link alone carries it")
	var link_src: String = FileAccess.get_file_as_string("res://server/net/host_link.gd")
	var auth_at: int = link_src.find("if not _authed.has(peer):")
	assert_gt(auth_at, 0)
	assert_gt(link_src.find('"knock_off":'), auth_at, "and only from a peer holding the link's token (test_host_link.gd)")
