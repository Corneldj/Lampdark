extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-04: the run-start kit (empty hands and belt; chalk, the Pocket Book and the lamp check);
## no-slot things are never items; the free-hand rule; two-handed actions hook the lamp.

const W = preload("res://tests/unit/mnr/belt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_run_start_kit() -> void:
	var s: Scenario = make({"seed": 1, "fixture": W.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var bob: MinerHandle = s.add_miner("bob", s.fixture.spot("b"))
	s.step(2)
	for h: MinerHandle in [ann, bob]:
		var b: HandsAndBelt = W.belt(s, h.entity_id)
		assert_null(b.lamp_hand, "the lamp hand starts empty")
		assert_null(b.free_hand)
		assert_eq(b.slots.size(), 4)
		for it: Item in b.slots:
			assert_null(it, "everything is found: the belt starts empty")
		assert_true(b.chalk)
		assert_true(b.pocket_book)
		assert_gt(b.lamp_check, 0, "each miner has a lamp check")
		assert_eq(b.held_items().size(), 0)
	assert_ne(W.belt(s, ann.entity_id).lamp_check, W.belt(s, bob.entity_id).lamp_check)


func test_no_slot_things_are_not_items() -> void:
	for name: String in ItemKinds.Kind.keys():
		assert_false(name in ["CHALK", "POCKET_BOOK", "LAMP_CHECK"], "%s can never be dropped, handed over or taken" % name)
	var b: HandsAndBelt = W.bare()
	for i: int in 4:
		assert_null(b.take_slot(i))
	assert_false(b.consume(ItemKinds.Kind.CANDLE, 1))
	assert_true(b.chalk and b.pocket_book and b.lamp_check == 7)
	var note: Item = Item.make(1, ItemKinds.Kind.NOTE)
	assert_eq(b.store(note), 0)
	assert_eq(b.notes, [note], "a found note goes into the Pocket Book, not a slot")
	for it: Item in b.slots:
		assert_null(it)


func test_lamps_and_cans_by_hand() -> void:
	var b: HandsAndBelt = W.bare()
	var lamp: Item = Item.make(1, ItemKinds.Kind.GAUZE_LAMP)
	b.store(lamp)
	assert_eq(b.lamp_hand, lamp, "a lamp goes to an empty lamp hand")
	var second: Item = Item.make(2, ItemKinds.Kind.ELECTRIC_LAMP)
	b.store(second)
	assert_eq(b.slots[0], second, "else a slot")
	var can: Item = Item.make(3, ItemKinds.Kind.PARAFFIN_CAN)
	assert_true(b.fits(can))
	b.store(can)
	assert_eq(b.free_hand, can, "a can rides in the free hand")
	assert_false(b.fits(Item.make(4, ItemKinds.Kind.PARAFFIN_CAN)), "one can at a time")


func test_free_hand_blocking() -> void:
	var b: HandsAndBelt = W.bare()
	assert_false(b.free_hand_blocked(&"pick_up"))
	for kind: ItemKinds.Kind in [ItemKinds.Kind.REVOLVER, ItemKinds.Kind.PARAFFIN_CAN, ItemKinds.Kind.FLARE]:
		b.free_hand = Item.make(1, kind)
		for action: StringName in [&"pick_up", &"crank", &"kit", &"flint"]:
			assert_true(b.free_hand_blocked(action), "%s blocks %s" % [ItemKinds.Kind.find_key(kind), action])
		for action: StringName in [&"feel", &"lever", &"phone"]:
			assert_false(b.free_hand_blocked(action), "%s still allows %s" % [ItemKinds.Kind.find_key(kind), action])
	b.free_hand = null
	b.two_handed = true
	assert_true(b.free_hand_blocked(&"lever"), "both hands busy")


func test_two_handed_hooks_the_lamp() -> void:
	var s: Scenario = make({"seed": 2, "fixture": W.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.step(1)
	var inv: InventorySystem = s.run.inventory
	var b: HandsAndBelt = W.belt(s, ann.entity_id)
	var lamp: Item = inv.world.make(ItemKinds.Kind.GAUZE_LAMP)
	assert_true(inv.give(s.run, ann.entity_id, lamp))
	assert_true(inv.begin_two_handed(s.run, ann.entity_id))
	assert_true(b.hooked, "the lamp hangs on the belt hook")
	assert_eq(b.lamp_hand, lamp)
	assert_eq(inv.held_bits(ann.entity_id) & 0xFF, ItemKinds.Kind.GAUZE_LAMP | 0x80)
	inv.end_two_handed(ann.entity_id)
	assert_false(b.hooked, "back in the hand when the action ends")
	for kind: ItemKinds.Kind in [ItemKinds.Kind.REVOLVER, ItemKinds.Kind.PARAFFIN_CAN, ItemKinds.Kind.FLARE]:
		b.free_hand = inv.world.make(kind)
		assert_false(inv.begin_two_handed(s.run, ann.entity_id), "refused with %s in the free hand" % ItemKinds.Kind.find_key(kind))
		assert_false(b.hooked)
	b.free_hand = null
	# A lit candle in the lamp hand is set down burning on the miner's tile.
	b.lamp_hand = inv.world.make(ItemKinds.Kind.CANDLE, 1, {"lit": true})
	assert_true(inv.begin_two_handed(s.run, ann.entity_id))
	assert_null(b.lamp_hand)
	var found: Array[int] = []
	for raw: Variant in inv.world.items.keys():
		var it: Item = inv.world.items[raw]
		if it.kind == ItemKinds.Kind.CANDLE:
			found.append(int(Variants.number(raw)))
	assert_eq(found.size(), 1)
	assert_eq(s.run.registry.get_entity(found[0]).tile(), s.fixture.spot("a"))
	assert_true(Variants.flag(inv.world.items[found[0]].state["lit"]), "still burning")
