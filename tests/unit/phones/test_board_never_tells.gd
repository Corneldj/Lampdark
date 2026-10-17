extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-13 (Gameplay §4.10's "never shows", §6.6): the operator is sent the board alone: each numbered
## flap's state, the cord's line and whether it is awake, in BoardWire's fixed bytes. Two boards whose
## phones hang in different places, called by different miners and with a line cut in a different
## spot, send the operator the same bytes: nothing names a place, the number-to-phone mapping, a
## caller or a cut's cause.

const W = preload("res://tests/unit/phones/board_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


## A board with one call waiting and one line cut; [the operator's bytes, what their client holds,
## the calling phone's number, its tile].
func _board(phone_at: int, caller: String, cut_at: Vector2i) -> Array:
	var s: Scenario = make(W.cfg(6101))
	W.camp(s)
	s.run.power.switch_closed = true
	var pc: Array = W.phone_and_caller(s, "p1", phone_at, caller)
	var p: PitPhone = pc[0]
	var h: MinerHandle = pc[1]
	var dead: PitPhone = W.P.phone(s, "p2", W.floor_tile(s, phone_at + 3))
	var op: MinerHandle = W.operator(s, "bob", 12)
	W.crank(s, h)
	dead.crossings = [[cut_at, 2]]
	s.run.phones.on_tiles_fallen(s.run, cut_at, [] as Array[Vector2i], 2)
	s.step(4)
	return [s.run.switchboard.view(s.run), op.connection.board.duplicate(true), p.number, p.tile]


func test_the_operator_is_sent_the_board_alone() -> void:
	var a: Array = _board(0, "ann", Vector2i(3, 3))
	var b: Array = _board(6, "cat", Vector2i(-2, 4))
	var a_tile: Vector2i = a[3]
	var b_tile: Vector2i = b[3]
	var number: int = Variants.whole(a[2])
	assert_ne(a_tile, b_tile, "two phones in two places")
	assert_eq(Variants.whole(b[2]), number, "on the same number")
	var a_bytes: PackedByteArray = a[0]
	var b_bytes: PackedByteArray = b[0]
	assert_eq(a_bytes.size(), BoardWire.SIZE, "the board's fixed size, whatever it holds")
	var a_told: Dictionary = a[1]
	var b_told: Dictionary = b[1]
	var keys: Array = a_told.keys()
	keys.sort()
	assert_eq(keys, ["awake", "cord", "flaps"], "flaps, the cord and whether it is awake: nothing else")
	var flaps: PackedByteArray = a_told["flaps"]
	assert_eq(flaps[number - 1], BoardWire.Flap.DOWN, "the call's flap down")
	assert_true(flaps.has(BoardWire.Flap.DARK), "the cut line dark")
	assert_eq(a_bytes, b_bytes, "the same bytes: no place, no caller, no cause")
	assert_eq(a_told, b_told, "and the operator's client holds the same")
