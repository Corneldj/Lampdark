extends "res://tests/scenario/kit/scenario_test.gd"
## UI-02's entry rules on the server: the table and the Manual open from an interact at them, the
## Pocket Book anywhere; refused while carrying two-handed, Grabbed or unconscious (Caught may read);
## Esc or B closes the table, the Pocket Book and the Manual at once; the board takes the 2 s sit
## (held, with the seat free) and the 2 s stand, which A cancels. Each client hears its own state.

const W = preload("res://tests/scenario/ui/closeup_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _seat_ticks() -> int:
	return roundi(Tuning.f(&"phones.seat_s") * Tuning.f(&"net.tick_hz"))


func test_the_table_and_the_manual_open_at_their_fixture_and_close_on_esc() -> void:
	var s: Scenario = W.camp(201, self)
	for kind: CloseupKind.Kind in [CloseupKind.Kind.MAP_TABLE, CloseupKind.Kind.MANUAL]:
		var h: MinerHandle = W.beside(s, "m%d" % kind, kind)
		assert_not_null(h)
		s.step(3)
		W.interact(s, h)
		s.step(8)
		assert_eq(W.kind_of(s, h), kind, "opened by an interact at its fixture")
		assert_eq(h.connection.closeup, {"kind": kind, "seat": CloseupKind.Seat.NONE}, "its client was told")
		W.ask(s, h, CloseupKind.Ask.CLOSE)
		s.step(8)
		assert_eq(W.kind_of(s, h), CloseupKind.Kind.NONE, "Esc or B closes it at once")
		assert_eq(int(Variants.number(h.connection.closeup["kind"])), CloseupKind.Kind.NONE)


func test_the_pocket_book_opens_anywhere_but_not_twice() -> void:
	var s: Scenario = W.camp(202, self)
	var deck: Vector2i = Basecamp.fixture(W.C.SEED, "cage_deck", s.run.base_camp.side)[0]["position"]
	var h: MinerHandle = s.add_miner("ann", deck)
	s.step(2)
	W.ask(s, h, CloseupKind.Ask.OPEN_POCKET_BOOK)
	s.step(2)
	assert_eq(W.kind_of(s, h), CloseupKind.Kind.POCKET_BOOK)
	var opens: int = s.run.closeups.history.filter(func(e: Dictionary) -> bool: return Variants.flag(e["open"])).size()
	W.ask(s, h, CloseupKind.Ask.OPEN_POCKET_BOOK)
	s.step(2)
	assert_eq(s.run.closeups.history.filter(func(e: Dictionary) -> bool: return Variants.flag(e["open"])).size(), opens, "already reading")
	W.ask(s, h, CloseupKind.Ask.CLOSE)
	s.step(2)
	assert_eq(W.kind_of(s, h), CloseupKind.Kind.NONE)


func test_refused_while_two_handed_grabbed_or_unconscious_but_caught_may_read() -> void:
	var s: Scenario = W.camp(203, self)
	var ann: MinerHandle = W.beside(s, "ann", CloseupKind.Kind.MAP_TABLE)
	var bob: MinerHandle = W.beside(s, "bob", CloseupKind.Kind.MAP_TABLE, 1)
	var cid: MinerHandle = W.beside(s, "cid", CloseupKind.Kind.MAP_TABLE, 2)
	var dot: MinerHandle = W.beside(s, "dot", CloseupKind.Kind.MAP_TABLE, 3)
	s.step(3)
	assert_true(s.run.inventory.begin_two_handed(s.run, ann.entity_id))
	s.run.miner_state.enter_grabbed(bob.entity_id, &"drag", 0)
	assert_true(s.run.falls.fall_unconscious(s.run, cid.entity_id, FallCause.Cause.MOTH_SMOTHER))
	s.run.miner_state.enter_caught(dot.entity_id, &"man_trap", 1)
	s.step(1)
	assert_eq(s.run.miner_state.life(bob.entity_id), MinerTransitions.Life.GRABBED)
	assert_eq(s.run.miner_state.life(cid.entity_id), MinerTransitions.Life.UNCONSCIOUS)
	assert_eq(s.run.miner_state.life(dot.entity_id), MinerTransitions.Life.CAUGHT)
	for h: MinerHandle in [ann, bob, cid, dot]:
		W.interact(s, h)
		W.ask(s, h, CloseupKind.Ask.OPEN_POCKET_BOOK)
	s.step(8)
	assert_eq(W.kind_of(s, ann), CloseupKind.Kind.NONE, "not while carrying two-handed")
	assert_eq(W.kind_of(s, bob), CloseupKind.Kind.NONE, "not while Grabbed")
	assert_eq(W.kind_of(s, cid), CloseupKind.Kind.NONE, "not while unconscious")
	assert_ne(W.kind_of(s, dot), CloseupKind.Kind.NONE, "a Caught miner may read (Proposed)")


func test_the_board_takes_two_seconds_to_sit_and_to_stand() -> void:
	var s: Scenario = W.camp(204, self)
	var ann: MinerHandle = W.beside(s, "ann", CloseupKind.Kind.SWITCHBOARD)
	var bob: MinerHandle = W.beside(s, "bob", CloseupKind.Kind.SWITCHBOARD, 1)
	s.step(3)
	var sit: int = _seat_ticks()
	# Let go early: no seat.
	W.interact(s, ann, sit - 10)
	s.step(sit + 5)
	assert_eq(W.kind_of(s, ann), CloseupKind.Kind.NONE, "released before 2 s: still standing")
	# Held to the end: seated, the board open; the client saw the sitting.
	var saw_sitting: Array[bool] = [false]
	s.on_tick = func(_sc: Scenario) -> void:
		if int(Variants.number(ann.connection.closeup.get("seat", 0))) == CloseupKind.Seat.SITTING:
			saw_sitting[0] = true
	W.interact(s, ann, sit + 10)
	s.step(sit - 2)
	assert_eq(W.kind_of(s, ann), CloseupKind.Kind.NONE, "not before 2 s")
	s.step(12)
	assert_eq(W.kind_of(s, ann), CloseupKind.Kind.SWITCHBOARD, "seated after 2 s")
	assert_true(saw_sitting[0], "its client heard it sitting down")
	# The seat is taken.
	W.interact(s, bob, sit + 10)
	s.step(sit + 15)
	assert_eq(W.kind_of(s, bob), CloseupKind.Kind.NONE, "one operator at a time")
	# B starts the stand; A cancels it; B again, and 2 s later the board closes.
	W.ask(s, ann, CloseupKind.Ask.CLOSE)
	s.step(3)
	assert_eq(int(Variants.number(ann.connection.closeup["seat"])), CloseupKind.Seat.STANDING)
	W.ask(s, ann, CloseupKind.Ask.STAY_SEATED)
	s.step(sit + 5)
	assert_eq(W.kind_of(s, ann), CloseupKind.Kind.SWITCHBOARD, "A cancelled the stand")
	W.ask(s, ann, CloseupKind.Ask.CLOSE)
	s.step(sit - 3)
	assert_eq(W.kind_of(s, ann), CloseupKind.Kind.SWITCHBOARD, "standing takes 2 s")
	s.step(5)
	assert_eq(W.kind_of(s, ann), CloseupKind.Kind.NONE, "stood up")
