extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-13 with CRT-11 (Gameplay §4.10, §6.6, §9.2): the Tapper's line renders for the operator alone.
## A stub of CRT-11's false drop on a line nobody is on: its buzzer an illusion event in the
## operator's frame, its flap laid over the operator's close-up. The operator's client shows the line
## down and hears the buzzer; the board itself holds the flap up and sounds nothing. Cat, standing at
## the board, hears no buzzer, is sent no board, and sees the cabinet with no flap down, as would
## anyone sitting at it after; a real call's drop she does see.

const W = preload("res://tests/unit/phones/board_world.gd")
const SW = preload("res://tests/unit/sound/signal_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


static func _buzzes_heard(h: MinerHandle) -> int:
	var n: int = 0
	for e: Dictionary in h.connection.events:
		if int(Variants.number(e["type"])) == NoiseTypes.Type.BUZZER:
			n += 1
	return n


## The cabinet as `h`'s client sees it at identity (FixtureKinds.read_switchboard), or {} if unseen.
static func _cabinet_seen(h: MinerHandle) -> Dictionary:
	var view: ReceivedView = h.connection.view
	if view == null:
		return {}
	for raw: Variant in view.entities.keys():
		var e: Dictionary = view.entities[raw]
		if int(Variants.number(e.get("size_or_kind", -1))) != SeenKind.Kind.FIXTURE or int(Variants.number(e.get("level", 0))) < 2:
			continue
		var bits: int = int(Variants.number(e.get("in_hand", 0)))
		if FixtureKinds.kind_of(bits) == FixtureKinds.Kind.SWITCHBOARD:
			return FixtureKinds.read_switchboard(bits)
	return {}


func test_the_false_drop_renders_on_the_operators_client_alone() -> void:
	var s: Scenario = make(W.cfg(5701))
	W.camp(s)
	s.run.power.switch_closed = true
	var p: PitPhone = W.P.phone(s, "p1", W.floor_tile(s, 0))
	var real: Array = W.phone_and_caller(s, "p2", 6, "ann")
	var p2: PitPhone = real[0]
	var ann: MinerHandle = real[1]
	var op: MinerHandle = W.operator(s, "bob", 12)
	var seats: Array[Dictionary] = Basecamp.fixture(s.run.base_camp.seed_value, "switchboard_seat", s.run.base_camp.side)
	var seat: Vector2i = seats[0]["position"]
	var board_at: Vector2 = s.run.registry.get_entity(s.run.switchboard.fixture).position
	var toward: float = rad_to_deg((board_at - (Vector2(seat) + Vector2(0.5, 0.5))).angle())
	var cat: MinerHandle = SW.miner(s, "cat", seat, toward, false)
	s.step(4)
	var before: Dictionary = _cabinet_seen(cat)
	assert_false(before.is_empty(), "Cat sees the cabinet at identity")
	if before.is_empty():
		return
	assert_true(Variants.flag(before["awake"]), "awake")
	# CRT-11's stub: the rock drops line p1's flap for the operator alone.
	var buzz: AudioRecord = AudioRecord.new()
	buzz.type = NoiseTypes.Type.BUZZER
	buzz.start_tick = s.run.tick + 1
	buzz.apparent = board_at
	buzz.level_np = Tuning.f(&"noise.buzzer_np")
	buzz.remaining_np = buzz.level_np - 2.0
	s.run.replication.append_illusion_event(op.slot, buzz.to_event())
	s.step(2)
	assert_eq(_buzzes_heard(op), 1, "the operator hears the buzzer")
	assert_eq(_buzzes_heard(cat), 0, "Cat, at the board, hears nothing")
	assert_eq(W.events_of(s, NoiseTypes.Type.BUZZER).size(), 0, "the board sounds nothing")
	assert_eq(W.flaps(s)[p.number - 1], BoardWire.Flap.UP, "the board holds the flap up")
	var mine: SwitchboardCloseup = autofree(SwitchboardCloseup.new())
	mine.set_board(op.connection.board)
	mine.illusion_flaps[p.number] = true
	assert_eq(mine.flap_of(p.number), BoardWire.Flap.DOWN, "the operator's close-up shows it down")
	var theirs: SwitchboardCloseup = autofree(SwitchboardCloseup.new())
	theirs.set_board(op.connection.board)
	assert_eq(theirs.flap_of(p.number), BoardWire.Flap.UP, "anyone else at the board sees it up")
	assert_true(cat.connection.board.is_empty(), "Cat is sent no board")
	assert_eq(int(Variants.number(_cabinet_seen(cat)["down"])), 0, "and sees no flap down on the cabinet")
	# A real call's drop shows on both.
	W.crank(s, ann)
	assert_eq(int(Variants.number(_cabinet_seen(cat)["down"])), 1, "a real drop she sees")
	assert_eq(_buzzes_heard(cat), 1, "and hears")
	mine.set_board(op.connection.board)
	assert_eq(mine.flap_of(p2.number), BoardWire.Flap.DOWN, "the operator sees the real drop")
	assert_eq(mine.flap_of(p.number), BoardWire.Flap.DOWN, "and the rock's")
