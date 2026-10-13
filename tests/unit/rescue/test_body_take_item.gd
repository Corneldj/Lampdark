extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-01: a teammate's 1 s Take moves one item from a body's belt into their own; releasing at
## 0.9 s takes nothing; a take that would not fit the taker's belt is refused.

const W = preload("res://tests/unit/mnr/belt_world.gd")

var _bob_holds: Array[int] = [0]


func before_all() -> void:
	assert_true(Tuning.load_server())


func _setup(run_seed: int) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": W.room()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var bob: MinerHandle = s.add_miner("bob", a + Vector2i(1, 0))
	s.step(1)
	var inv: InventorySystem = s.run.inventory
	assert_true(inv.give(s.run, ann.entity_id, inv.world.make(ItemKinds.Kind.SPANNER)))
	assert_true(inv.give(s.run, ann.entity_id, inv.world.make(ItemKinds.Kind.HEALING_KIT)))
	assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.BLAST))
	s.step(2)
	_bob_holds[0] = 0
	inv.holds_source = func(_run: RunState, slot: int) -> int: return _bob_holds[0] if slot == bob.slot else 0
	return [s, ann, bob]


func test_take_moves_one_item() -> void:
	var parts: Array = _setup(1)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var bob: MinerHandle = parts[2]
	var a: TimedAction = s.run.falls.take_item_action(s.run, bob.entity_id, ann.entity_id, 1)
	assert_eq(a.ticks_needed, 20, "1 s")
	assert_true(s.run.inventory.start_action(s.run, a))
	_bob_holds[0] = InputRecord.HOLD_INTERACT
	s.step(22)
	assert_null(W.belt(s, ann.entity_id).slots[1], "the kit left the body")
	assert_eq(W.belt(s, ann.entity_id).slots[0].kind, ItemKinds.Kind.SPANNER, "one item only")
	assert_eq(W.belt(s, bob.entity_id).slots[0].kind, ItemKinds.Kind.HEALING_KIT, "into the taker's belt")


func test_release_at_09_s_takes_nothing() -> void:
	var parts: Array = _setup(2)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var bob: MinerHandle = parts[2]
	assert_true(s.run.inventory.start_action(s.run, s.run.falls.take_item_action(s.run, bob.entity_id, ann.entity_id, 0)))
	_bob_holds[0] = InputRecord.HOLD_INTERACT
	s.step(18)
	_bob_holds[0] = 0
	s.step(10)
	assert_eq(W.belt(s, ann.entity_id).slots[0].kind, ItemKinds.Kind.SPANNER, "released at 0.9 s: nothing taken")
	assert_null(W.belt(s, bob.entity_id).slots[0])


func test_refused_if_it_will_not_fit() -> void:
	var parts: Array = _setup(3)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var bob: MinerHandle = parts[2]
	var inv: InventorySystem = s.run.inventory
	for k: ItemKinds.Kind in [ItemKinds.Kind.HAMMER, ItemKinds.Kind.CROWBAR, ItemKinds.Kind.FUSE, ItemKinds.Kind.MAGNETO]:
		assert_true(inv.give(s.run, bob.entity_id, inv.world.make(k)))
	var a: TimedAction = s.run.falls.take_item_action(s.run, bob.entity_id, ann.entity_id, 0)
	var ends: Array[StringName] = []
	a.cancelled.connect(func(_x: TimedAction, reason: StringName) -> void: ends.append(reason))
	assert_true(inv.start_action(s.run, a))
	_bob_holds[0] = InputRecord.HOLD_INTERACT
	s.step(25)
	assert_eq(ends, [TimedAction.TARGET] as Array[StringName], "bob's belt is full: refused")
	assert_eq(W.belt(s, ann.entity_id).slots[0].kind, ItemKinds.Kind.SPANNER)
