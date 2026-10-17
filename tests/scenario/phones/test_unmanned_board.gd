extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-13 (Gameplay §4.10, §6.6, §13.9; A.3): nobody at the board. A crank on a live line drops its
## flap, and the 12 np buzzer sounds at the board, heard in base camp, again every
## phones.buzzer_repeat_s while the caller waits. Nothing answers it: not the board, not the Hired
## Hand standing at the seat (Hands never sit), and no client is sent the board. The caller hangs
## up: the flap goes up, and the buzzing stops.

const W = preload("res://tests/unit/phones/board_world.gd")
const H = preload("res://tests/unit/hands/hand_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


static func _buzzes_heard(h: MinerHandle) -> int:
	var n: int = 0
	for e: Dictionary in h.connection.events:
		if int(Variants.number(e["type"])) == NoiseTypes.Type.BUZZER:
			n += 1
	return n


func test_calls_buzz_and_nothing_answers() -> void:
	var s: Scenario = make(W.cfg(5601))
	W.camp(s)
	s.run.power.switch_closed = true
	var pc: Array = W.phone_and_caller(s, "p1", 0, "ann")
	var p: PitPhone = pc[0]
	var ann: MinerHandle = pc[1]
	var bob: MinerHandle = s.add_miner("bob", W.floor_tile(s, 5))
	bob.brain = null
	var seats: Array[Dictionary] = Basecamp.fixture(s.run.base_camp.seed_value, "switchboard_seat", s.run.base_camp.side)
	var seat: Vector2i = seats[0]["position"]
	var hand: int = H.hand(s, seat, 4)
	s.step(2)
	W.crank(s, ann)
	assert_eq(p.state, PitPhone.State.CALLING, "her call reaches the board")
	assert_eq(W.flaps(s)[p.number - 1], BoardWire.Flap.DOWN, "its flap down")
	var repeat: int = roundi(Tuning.f(&"phones.buzzer_repeat_s") * Tuning.f(&"net.tick_hz"))
	s.step(repeat * 7)
	var buzz: Array[NoiseSystem.Event] = W.events_of(s, NoiseTypes.Type.BUZZER)
	assert_eq(buzz.size(), 8, "again every %d ticks while she waits" % repeat)
	assert_eq(buzz[0].level_np, 12.0, "at 12 np")
	assert_eq(_buzzes_heard(bob), 8, "each heard in base camp")
	assert_eq(p.state, PitPhone.State.CALLING, "nothing answers")
	assert_eq(p.operator, -1)
	assert_true(Variants.flag(s.run.crew.is_hand_driven.call(hand)), "a Hired Hand at the seat")
	assert_eq(s.run.closeups.operator(), 0, "nobody sits: never the Hand")
	assert_eq(s.run.switchboard.cord, 0)
	assert_eq(ann.connection.board_messages + bob.connection.board_messages, 0, "no client is sent the board")
	# She hangs up: the flap goes up, and the buzzing stops.
	W.P.press(s, ann)
	assert_eq(p.state, PitPhone.State.IDLE, "hung up")
	assert_eq(W.flaps(s)[p.number - 1], BoardWire.Flap.UP, "the flap up")
	var after: int = W.events_of(s, NoiseTypes.Type.BUZZER).size()
	s.step(repeat * 3)
	assert_eq(W.events_of(s, NoiseTypes.Type.BUZZER).size(), after, "the buzzing stops")
