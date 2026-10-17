extends "res://tests/scenario/kit/scenario_test.gd"
## MOD-08 (Gameplay §13.9, §13.10, §13.11): a Hand takes a dropped player's conscious miner where it
## stands, keeping its belt and its lamp, turned down on the hook, and hands it back as it is when the
## player returns. A kicked or ejected player's Hand keeps their lamp, and the rest of their belt
## drops at their feet (the revolver too). A taken miner is Hand-driven but never a Hired Hand of its
## own: it still counts for the wipe and the crew.

const R = preload("res://tests/unit/mnr/revolver_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")
const HW = preload("res://tests/unit/hands/hand_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _world(run_seed: int) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": R.hall()})
	R.lit(s)
	var ann: MinerHandle = R.miner(s, "ann", Vector2i(3, 2))
	var bob: MinerHandle = R.miner(s, "bob", Vector2i(6, 2))
	s.step(3)
	return [s, ann, bob]


func _belt(s: Scenario, h: MinerHandle) -> void:
	var w: ItemWorld = s.run.inventory.world
	assert_true(s.run.inventory.give(s.run, h.entity_id, w.make(ItemKinds.Kind.SPANNER)))
	assert_true(s.run.inventory.give(s.run, h.entity_id, w.make(ItemKinds.Kind.REVOLVER)))


func test_a_drop_keeps_tile_belt_and_lamp_and_is_handed_back() -> void:
	var w: Array = _world(4901)
	var s: Scenario = w[0]
	var bob: MinerHandle = w[2]
	var l: GauzeLamp = L.lit_in_hand(s, bob, LampRules.WICK_UP)
	_belt(s, bob)
	s.step(2)
	var at: Vector2 = HW.pos(s, bob.entity_id)
	bob.at(s.run.tick).disconnect_at()
	assert_true(s.run_until(func(sc: Scenario) -> bool: return sc.run.hands.is_hand_driven(bob.entity_id), 200))
	assert_lt(HW.pos(s, bob.entity_id).distance_to(at), 0.2, "taken where it stands")
	assert_eq(l.place, LampRules.Place.HOOK, "its lamp on the hook")
	assert_eq(l.wick, LampRules.WICK_DOWN, "turned down")
	var h: HandsAndBelt = s.run.inventory.hands_of(bob.entity_id)
	assert_eq(h.count_of(ItemKinds.Kind.SPANNER), 1, "the belt kept")
	assert_eq(h.count_of(ItemKinds.Kind.REVOLVER), 1)
	assert_false(s.run.hands.is_hand(bob.entity_id), "a player's miner, never a Hired Hand of its own")
	assert_true(RunOutcomes.counted(s.run).has(bob.entity_id), "it still counts")
	var back: MinerHandle = s.rejoin("bob")
	s.step(10)
	assert_eq(back.entity_id, bob.entity_id)
	assert_false(s.run.hands.is_hand_driven(bob.entity_id), "handed back")
	assert_eq(l.place, LampRules.Place.HOOK, "the lamp still on the belt until he takes it")


func test_a_kick_keeps_the_lamp_and_drops_the_belt() -> void:
	for mode: DropHandler.Takeover in [DropHandler.Takeover.KICKED, DropHandler.Takeover.EJECTED]:
		var w: Array = _world(4902 + mode)
		var s: Scenario = w[0]
		var bob: MinerHandle = w[2]
		var l: GauzeLamp = L.lit_in_hand(s, bob)
		_belt(s, bob)
		s.step(2)
		var at: Vector2 = HW.pos(s, bob.entity_id)
		assert_true(s.run.drops.remove_player(s.run, "bob", "test", mode))
		s.step(3)
		assert_true(s.run.hands.is_hand_driven(bob.entity_id), "a Hand takes the place")
		var h: HandsAndBelt = s.run.inventory.hands_of(bob.entity_id)
		assert_eq(s.run.lamps.lamp_in_hand(bob.entity_id), l, "the Hand keeps the lamp")
		assert_eq(h.count_of(ItemKinds.Kind.SPANNER) + h.count_of(ItemKinds.Kind.REVOLVER), 0, "the rest of the belt dropped")
		var lying: Array[int] = []
		for id: int in s.run.registry.ids():
			var e: SimEntity = s.run.registry.get_entity(id)
			var it: Item = s.run.inventory.world.item_at(id)
			if it != null and e.position.distance_to(at) < 0.5 and (it.kind == ItemKinds.Kind.SPANNER or it.kind == ItemKinds.Kind.REVOLVER):
				lying.append(it.kind)
		lying.sort()
		assert_eq(lying, [ItemKinds.Kind.REVOLVER, ItemKinds.Kind.SPANNER] as Array[int] if ItemKinds.Kind.REVOLVER < ItemKinds.Kind.SPANNER
			else [ItemKinds.Kind.SPANNER, ItemKinds.Kind.REVOLVER] as Array[int], "at its feet (%s)" % DropHandler.Takeover.find_key(mode))
