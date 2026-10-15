extends "res://tests/scenario/kit/scenario_test.gd"
## UI-02: while a close-up is open the miner stands where they are. Over 30 s with movement, a turn
## and every mine hold sent, the position and facing do not change and nothing happens; closed, the
## same inputs move them again.

const W = preload("res://tests/scenario/ui/closeup_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_thirty_seconds_with_movement_held() -> void:
	var s: Scenario = W.camp(211, self)
	var ann: MinerHandle = s.add_miner("ann", _deck(s))
	s.step(3)
	W.ask(s, ann, CloseupKind.Ask.OPEN_POCKET_BOOK)
	s.step(8)
	assert_eq(W.kind_of(s, ann), CloseupKind.Kind.POCKET_BOOK)
	var e: SimEntity = s.run.registry.get_entity(ann.entity_id)
	var at: Vector2 = e.position
	var facing: int = s.run.movement.facing_of(ann.slot)
	var ticks: int = roundi(30.0 * Tuning.f(&"net.tick_hz"))
	var t0: int = s.run.tick + 1
	ann.at(t0).move(0.0, InputRecord.Gait.RUN, ticks)
	ann.at(t0).face(180.0)
	ann.at(t0).hold(InputRecord.HOLD_INTERACT | InputRecord.HOLD_USE | InputRecord.HOLD_SET_DOWN, ticks)
	var moved: Array[int] = [0]
	s.on_tick = func(sc: Scenario) -> void:
		if sc.run.registry.get_entity(ann.entity_id).position != at:
			moved[0] += 1
	s.step(ticks)
	assert_eq(moved[0], 0, "not one tick out of place")
	assert_eq(e.position, at)
	assert_eq(s.run.movement.facing_of(ann.slot), facing, "facing held")
	assert_eq(W.kind_of(s, ann), CloseupKind.Kind.POCKET_BOOK, "still reading")
	W.ask(s, ann, CloseupKind.Ask.CLOSE)
	s.step(8)
	ann.at(s.run.tick + 1).move(0.0, InputRecord.Gait.WALK, 20)
	s.step(25)
	assert_ne(e.position, at, "closed, the miner walks again")


func _deck(s: Scenario) -> Vector2i:
	var deck: Vector2i = Basecamp.fixture(W.C.SEED, "cage_deck", s.run.base_camp.side)[0]["position"]
	return deck
