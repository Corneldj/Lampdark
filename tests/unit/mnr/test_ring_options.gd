extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-05: with stub options registered for the other owners (cure, free, the silent pull, lay),
## each target state shows exactly the table's options, filtered by what the actor carries; no
## both-hold option is offered with a Hired Hand; hand over completes in 1 s and is refused when the
## receiver has no room.

const W = preload("res://tests/unit/mnr/belt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")
const R = preload("res://tests/unit/mnr/ring_world.gd")

const UP: int = MinerTransitions.Life.UPRIGHT
const CAUGHT: int = MinerTransitions.Life.CAUGHT
const GRABBED: int = MinerTransitions.Life.GRABBED
const DOWN: int = MinerTransitions.Life.UNCONSCIOUS
const DEAD: int = MinerTransitions.Life.DEAD


func before_all() -> void:
	assert_true(Tuning.load_server())


func _stubs(s: Scenario) -> void:
	var reg: RingOptions = s.run.ring.registry
	var nothing: Callable = func(run: RunState, actor: int, _t: int) -> TimedAction: return TimedAction.make(actor, &"stub", 1.0, InputRecord.HOLD_INTERACT)
	var has_kit: Callable = func(run: RunState, actor: int, _t: int) -> bool: return run.inventory.has(actor, ItemKinds.Kind.HEALING_KIT)
	reg.register("cure", [UP, CAUGHT, DOWN] as Array[int], has_kit, nothing)
	reg.register("free", [CAUGHT] as Array[int], Callable(), nothing)
	reg.register("silent_pull", [GRABBED] as Array[int], Callable(), nothing)
	reg.register("lay", [DOWN, DEAD] as Array[int], Callable(), nothing)


func _offered(s: Scenario, actor: MinerHandle, target: MinerHandle) -> Array[String]:
	return s.run.ring.registry.offered(s.run, actor.entity_id, target.entity_id)


func test_by_state_and_kit() -> void:
	var s: Scenario = make({"seed": 1, "fixture": W.room()})
	var pair: Array = R.pair(s)
	var ann: MinerHandle = pair[0]
	var bob: MinerHandle = pair[1]
	_stubs(s)
	var inv: InventorySystem = s.run.inventory
	# Ann carries nothing: only what needs nothing.
	assert_eq(_offered(s, ann, bob), [] as Array[String], "upright, empty-handed: nothing to offer")
	L.lit_in_hand(s, bob)
	assert_eq(_offered(s, ann, bob), ["douse"] as Array[String], "his open lamp: douse")
	L.lit_in_hand(s, ann)
	assert_true(inv.give(s.run, ann.entity_id, inv.world.make(ItemKinds.Kind.HEALING_KIT)))
	assert_eq(_offered(s, ann, bob), ["hand_over", "douse", "share_oil", "cure"] as Array[String], "her selected kit, both lamps, a kit")
	s.run.miner_state.enter_caught(bob.entity_id, &"man_trap", 1)
	s.step(2)
	assert_eq(_offered(s, ann, bob), ["hand_over", "douse", "share_oil", "cure", "free"] as Array[String], "caught: free too")
	s.run.miner_state.release_caught(bob.entity_id, "test")
	s.step(1)
	s.run.miner_state.enter_grabbed(bob.entity_id, &"pin", 0)
	s.step(2)
	assert_eq(_offered(s, ann, bob), ["silent_pull"] as Array[String], "grabbed: the silent pull only")


func test_bodies() -> void:
	var s: Scenario = make({"seed": 2, "fixture": W.room()})
	var pair: Array = R.pair(s)
	var ann: MinerHandle = pair[0]
	var bob: MinerHandle = pair[1]
	_stubs(s)
	var inv: InventorySystem = s.run.inventory
	assert_true(inv.give(s.run, bob.entity_id, inv.world.make(ItemKinds.Kind.SPANNER)))
	assert_true(inv.give(s.run, bob.entity_id, inv.world.make(ItemKinds.Kind.FUSE, 2)))
	assert_true(inv.give(s.run, ann.entity_id, inv.world.make(ItemKinds.Kind.HEALING_KIT)))
	s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.BLAST)
	s.step(2)
	# MNR-14 lists lay right after lift, as §4.3 does.
	assert_eq(_offered(s, ann, bob), ["lift", "lay", "take:0", "take:1", "cure"] as Array[String], "unconscious")
	s.run.miner_state.kill(bob.entity_id, "test")
	s.step(2)
	assert_eq(_offered(s, ann, bob), ["lift", "lay", "take:0", "take:1"] as Array[String], "dead: no cure")


func test_no_both_hold_with_a_hand() -> void:
	var s: Scenario = make({"seed": 3, "fixture": W.room()})
	var pair: Array = R.pair(s)
	var ann: MinerHandle = pair[0]
	var bob: MinerHandle = pair[1]
	L.lit_in_hand(s, ann)
	L.lit_in_hand(s, bob)
	assert_true(_offered(s, ann, bob).has("share_oil"))
	s.run.crew.is_hand_driven = func(e: int) -> bool: return e == bob.entity_id
	var offered: Array[String] = _offered(s, ann, bob)
	assert_false(offered.has("share_oil") or offered.has("pass_flame"), "no both-hold with a Hired Hand")
	assert_true(offered.has("douse"), "a Hand can still be doused")
	assert_false(s.run.ring.open(s.run, bob.entity_id, ann.entity_id), "and never acts through the ring")


func test_hand_over() -> void:
	var s: Scenario = make({"seed": 4, "fixture": W.room()})
	var pair: Array = R.pair(s)
	var ann: MinerHandle = pair[0]
	var bob: MinerHandle = pair[1]
	var inv: InventorySystem = s.run.inventory
	var spanner: Item = inv.world.make(ItemKinds.Kind.SPANNER)
	assert_true(inv.give(s.run, ann.entity_id, spanner))
	R.tap(s, ann)
	var seen: Array[TimedAction] = []
	s.on_tick = func(sc: Scenario) -> void:
		var act: TimedAction = sc.run.inventory.actions.get(ann.entity_id, null)
		if act != null and not seen.has(act):
			seen.append(act)
	assert_true(R.pick_and_hold(s, ann, "hand_over", 25))
	assert_eq(seen[0].ticks_needed, 20, "1 s")
	assert_eq(inv.hands_of(bob.entity_id).slots[0], spanner, "handed over")
	assert_false(s.run.ring.rings.has(ann.entity_id), "the ring closes when done")
	# No room: four tools on his belt, so a fifth is not offered.
	for k: ItemKinds.Kind in [ItemKinds.Kind.HAMMER, ItemKinds.Kind.CROWBAR, ItemKinds.Kind.FUSE]:
		assert_true(inv.give(s.run, bob.entity_id, inv.world.make(k)))
	assert_true(inv.give(s.run, ann.entity_id, inv.world.make(ItemKinds.Kind.MAGNETO)))
	assert_false(_offered(s, ann, bob).has("hand_over"), "refused when the receiver has no room")
