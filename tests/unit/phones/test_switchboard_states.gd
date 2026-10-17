extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-13 (Gameplay §6.6, §4.10; A.3): the board's lines. Before Power it is inert: no drop, no
## buzzer, a silent headset. After it, a crank on a live line drops its flap and sounds the 12 np
## buzzer at the board, again every phones.buzzer_repeat_s while nobody answers. Plugging in connects
## the call both ways (the flap goes up); holding it leaves the caller on the line in hiss, its flap
## marked held, and the cord free; plugging another line holds the call the cord was in. Ringing a
## live line sounds LFT-12's 20 np bell; a dark or unassigned number rings nothing. A cut line is
## dark for the run.

const W = preload("res://tests/unit/phones/board_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_inert_before_power() -> void:
	var s: Scenario = make(W.cfg(5201))
	W.camp(s)
	var pc: Array = W.phone_and_caller(s, "p1", 0, "ann")
	var p: PitPhone = pc[0]
	var ann: MinerHandle = pc[1]
	var op: MinerHandle = W.operator(s, "bob", 3)
	W.crank(s, ann)
	assert_eq(W.flaps(s)[p.number - 1], BoardWire.Flap.UP, "no drop")
	assert_eq(W.events_of(s, NoiseTypes.Type.BUZZER).size(), 0, "no buzzer")
	assert_false(Variants.flag(op.connection.board.get("awake", true)), "the operator's board is dead")
	W.ask(s, op, BoardWire.Verb.RING, p.number)
	assert_eq(W.events_of(s, NoiseTypes.Type.PHONE_BELL).size(), 0, "and rings nothing")


func test_drops_buzzes_plugs_holds_and_rings() -> void:
	var s: Scenario = make(W.cfg(5202))
	W.camp(s)
	s.run.power.switch_closed = true
	var first: Array = W.phone_and_caller(s, "p1", 0, "ann")
	var second: Array = W.phone_and_caller(s, "p2", 4, "cat")
	var p1: PitPhone = first[0]
	var ann: MinerHandle = first[1]
	var p2: PitPhone = second[0]
	var cat: MinerHandle = second[1]
	var op: MinerHandle = W.operator(s, "bob", 8)
	W.crank(s, ann)
	assert_eq(W.flaps(s)[p1.number - 1], BoardWire.Flap.DOWN, "her flap drops")
	var buzz: Array[NoiseSystem.Event] = W.events_of(s, NoiseTypes.Type.BUZZER)
	assert_eq(buzz.size(), 1, "the buzzer")
	assert_eq(buzz[0].level_np, 12.0, "at 12 np")
	assert_true(s.run.base_camp.inside_tiles.has(buzz[0].origins[0]), "at the board, in base camp")
	var repeat: int = roundi(Tuning.f(&"phones.buzzer_repeat_s") * Tuning.f(&"net.tick_hz"))
	s.step(repeat * 2)
	assert_eq(W.events_of(s, NoiseTypes.Type.BUZZER).size(), 3, "again every %d ticks while unanswered" % repeat)
	var seen: PackedByteArray = op.connection.board.get("flaps", PackedByteArray())
	assert_eq(seen[p1.number - 1], BoardWire.Flap.DOWN, "the operator's close-up shows the drop")
	# Plug in: connected both ways, the flap up, the buzzer stops.
	W.ask(s, op, BoardWire.Verb.PLUG, p1.number)
	assert_eq(p1.state, PitPhone.State.ON_CALL, "connected")
	assert_true(Variants.dict(s.run.voice.direct.get(ann.slot, {})).has(op.slot), "voice both ways")
	assert_eq(W.flaps(s)[p1.number - 1], BoardWire.Flap.UP, "the flap reset")
	assert_eq(s.run.switchboard.cord, p1.number, "the cord in her line")
	var buzzes: int = W.events_of(s, NoiseTypes.Type.BUZZER).size()
	s.step(repeat * 2)
	assert_eq(W.events_of(s, NoiseTypes.Type.BUZZER).size(), buzzes, "answered: no more buzzing")
	# Cat calls too; plugging her line holds Ann's.
	W.crank(s, cat)
	assert_eq(W.flaps(s)[p2.number - 1], BoardWire.Flap.DOWN)
	W.ask(s, op, BoardWire.Verb.PLUG, p2.number)
	assert_eq(p1.state, PitPhone.State.HELD, "Ann held")
	assert_eq(W.flaps(s)[p1.number - 1], BoardWire.Flap.HELD, "her flap marked held")
	assert_false(Variants.dict(s.run.voice.direct.get(ann.slot, {})).has(op.slot), "her line quiet")
	assert_ne(int(Variants.number(OwnStatus.of(s.run, ann.entity_id)["flags"])) & StatusWire.LINE_HISS, 0, "she hears hiss")
	assert_eq(p2.state, PitPhone.State.ON_CALL, "Cat on the line")
	# Hold Cat: the cord free, Cat held; back to Ann.
	W.ask(s, op, BoardWire.Verb.HOLD, 0)
	assert_eq(p2.state, PitPhone.State.HELD)
	assert_eq(s.run.switchboard.cord, 0, "the cord free")
	W.ask(s, op, BoardWire.Verb.PLUG, p1.number)
	assert_eq(p1.state, PitPhone.State.ON_CALL, "back to Ann")
	assert_eq(int(Variants.number(OwnStatus.of(s.run, ann.entity_id)["flags"])) & StatusWire.LINE_HISS, 0, "no more hiss")
	# Pull the cord: Ann's call ends, the operator's ear hisses until the cord is out.
	W.ask(s, op, BoardWire.Verb.PLUG, p1.number)
	assert_eq(p1.caller, 0, "the cord pulled: her call ended")
	assert_eq(s.run.switchboard.cord, 0)
	# Ring: a live line's bell; a dark or unassigned number nothing.
	W.ask(s, op, BoardWire.Verb.RING, p1.number)
	var bells: Array[NoiseSystem.Event] = W.events_of(s, NoiseTypes.Type.PHONE_BELL)
	assert_eq(bells.size(), 1, "a live line's bell")
	assert_eq(bells[0].level_np, 20.0, "at 20 np")
	assert_true(bells[0].origins.has(p1.tile), "at its phone")
	var unassigned: int = 1
	while s.run.phones.of_number(unassigned) != null:
		unassigned += 1
	W.ask(s, op, BoardWire.Verb.RING, unassigned)
	assert_eq(W.events_of(s, NoiseTypes.Type.PHONE_BELL).size(), 1, "an unassigned number rings nothing")
	# A cut: dark for the run.
	s.run.phones.on_tiles_fallen(s.run, Vector2i.ZERO, [] as Array[Vector2i], 1) # no crossing: nothing
	p1.crossings = [[Vector2i(3, 3), 2]]
	s.run.phones.on_tiles_fallen(s.run, Vector2i(3, 3), [] as Array[Vector2i], 2)
	s.step(2)
	assert_eq(W.flaps(s)[p1.number - 1], BoardWire.Flap.DARK, "a cut line dark")
	W.ask(s, op, BoardWire.Verb.RING, p1.number)
	assert_eq(W.events_of(s, NoiseTypes.Type.PHONE_BELL).size(), 1, "and it rings nothing")
	s.step(200)
	assert_eq(W.flaps(s)[p1.number - 1], BoardWire.Flap.DARK, "for the run")
	assert_true(Variants.flag(op.connection.board.get("awake", false)), "the operator's board awake")
	var shown: PackedByteArray = op.connection.board.get("flaps", PackedByteArray())
	assert_eq(shown[p1.number - 1], BoardWire.Flap.DARK, "and shows it dark")
