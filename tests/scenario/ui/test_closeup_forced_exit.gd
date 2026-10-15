extends "res://tests/scenario/kit/scenario_test.gd"
## UI-02: a close-up shuts at once, in the tick it happens, when its reader is Grabbed, falls
## unconscious or dies; Caught does not shut it (Proposed). The board is left without the stand.

const W = preload("res://tests/scenario/ui/closeup_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_grabbed_unconscious_or_dead_shuts_it_at_once() -> void:
	var s: Scenario = W.camp(231, self)
	var miners: Array[MinerHandle] = []
	for i: int in 4:
		miners.append(W.beside(s, "m%d" % i, CloseupKind.Kind.MAP_TABLE, i))
	s.step(3)
	for h: MinerHandle in miners:
		W.ask(s, h, CloseupKind.Ask.OPEN_POCKET_BOOK)
	s.step(8)
	for h: MinerHandle in miners:
		assert_eq(W.kind_of(s, h), CloseupKind.Kind.POCKET_BOOK)
	s.run.miner_state.enter_grabbed(miners[0].entity_id, &"drag", 0)
	assert_true(s.run.falls.fall_unconscious(s.run, miners[1].entity_id, FallCause.Cause.MOTH_SMOTHER))
	s.run.miner_state.kill(miners[2].entity_id, "test")
	s.run.miner_state.enter_caught(miners[3].entity_id, &"man_trap", 1)
	var tick: int = s.run.tick
	s.step(1)
	for i: int in 3:
		assert_eq(W.kind_of(s, miners[i]), CloseupKind.Kind.NONE, "miner %d's close-up shut" % i)
		var shut: Array = s.run.closeups.history.filter(func(e: Dictionary) -> bool:
			return int(Variants.number(e["entity"])) == miners[i].entity_id and not Variants.flag(e["open"]))
		assert_eq(shut.size(), 1)
		if shut.size() == 1:
			assert_eq(int(Variants.number(Variants.dict(shut[0])["tick"])), tick, "in the same tick")
			assert_string_starts_with(str(Variants.dict(shut[0])["cause"]), "forced:")
	assert_eq(W.kind_of(s, miners[3]), CloseupKind.Kind.POCKET_BOOK, "Caught reads on")


func test_the_board_is_left_at_once_on_a_fall() -> void:
	var s: Scenario = W.camp(232, self)
	var ann: MinerHandle = W.beside(s, "ann", CloseupKind.Kind.SWITCHBOARD)
	s.step(3)
	W.interact(s, ann, roundi(Tuning.f(&"phones.seat_s") * Tuning.f(&"net.tick_hz")) + 10)
	s.step(60)
	assert_eq(W.kind_of(s, ann), CloseupKind.Kind.SWITCHBOARD)
	assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.MOTH_SMOTHER))
	s.step(1)
	assert_eq(W.kind_of(s, ann), CloseupKind.Kind.NONE, "no 2 s stand for the fallen")
	assert_eq(s.run.closeups.operator(), 0, "the seat is free")
