extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-13 with VIS-09 (Gameplay §4.10's dangers, §7.2): an awake Moth within moth.tell_reach_tiles of
## the seated operator sets the dust flag on their own frame, blinded though they are, and the board's
## close-up sifts dust over the brass while it is set: evenly over the whole face, never from a side,
## so it says nothing of where the Moth is. Asleep, no dust.

const W = preload("res://tests/unit/phones/board_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_dust_sifts_over_the_brass_while_the_flag_is_set() -> void:
	var s: Scenario = make(W.cfg(6001))
	W.camp(s)
	s.run.power.switch_closed = true
	var west: Gate = s.run.base_camp.gate_system.gate("west")
	var op: MinerHandle = s.add_miner("bob", west.middle() - west.outward * 2)
	op.brain = null
	W.seat(s, op)
	s.place_creature(WorldIds.EntityKind.MOTH, west.middle() + west.outward * 4)
	var m: Moth = s.run.creatures.creature_of_kind(WorldIds.EntityKind.MOTH)
	s.step(4)
	var near: bool = s.run.registry.get_entity(op.entity_id).position.distance_to(m.position(s.run)) <= Tuning.f(&"moth.tell_reach_tiles")
	assert_true(near, "the Moth within its tell's reach of the board")
	assert_false(op.connection.view.dust, "asleep: no dust")
	m.waker = {}
	m.enter(s.run, &"prowl", "test")
	m.awake.begin(s.run, m, false)
	s.step(4)
	assert_eq(op.connection.view.tiles.size() + op.connection.view.entities.size(), 0, "the operator reads the board, blind to the room")
	assert_true(op.connection.view.dust, "the flag rides the operator's frame")
	var board: SwitchboardCloseup = autofree(SwitchboardCloseup.new())
	board.set_anchors_preset(Control.PRESET_TOP_LEFT)
	board.size = Vector2(1280, 800)
	board.set_board(op.connection.board)
	assert_eq(board.dust_specks(1.0).size(), 0, "no dust until the client passes the flag on")
	board.set_dust(op.connection.view.dust)
	var specks: PackedVector2Array = board.dust_specks(1.0)
	assert_gt(specks.size(), 0, "dust over the brass")
	var left: int = 0
	for p: Vector2 in specks:
		assert_true(board.face().grow(0.5).has_point(p), "on the board's face")
		if p.x < board.size.x * 0.5:
			left += 1
	assert_eq(left * 2, specks.size(), "as much on the left as the right: from no side")
	assert_ne(board.dust_specks(1.0), board.dust_specks(2.0), "sifting")
	board.set_dust(false)
	assert_eq(board.dust_specks(1.0).size(), 0, "no flag, no dust")
