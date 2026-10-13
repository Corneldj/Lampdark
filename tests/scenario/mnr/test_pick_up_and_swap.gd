extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-04 through real inputs: interact held 1 s on a seen item picks it up; an unseen, unfelt
## one is refused; set-down lays the selected item on the faced tile in 1 s; using a lamp's slot
## swaps it with the lamp in hand. The owner's client gets its belt; another client sees only what
## is in the miner's hands, on its identity record, and never its belt.

const W = preload("res://tests/unit/mnr/belt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _kinds_in_slots(inventory: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for raw: Variant in Variants.array(inventory.get("slots", [])):
		out.append(int(Variants.number(Variants.array(raw)[0])))
	return out


func test_pick_up_set_down_and_swap() -> void:
	var s: Scenario = make({"seed": 11, "fixture": W.room()})
	W.light(s)
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var bob: MinerHandle = s.add_miner("bob", s.fixture.spot("b"))
	var inv: InventorySystem = s.run.inventory
	var spanner: int = W.put(s, ItemKinds.Kind.SPANNER, a + Vector2i(1, 0))
	ann.at(s.run.tick).face(0.0)
	bob.at(s.run.tick).face(180.0)
	s.step(4)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 15)
	s.step(25)
	assert_true(inv.world.items.has(spanner), "released after 15 ticks: still on the floor")
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 22)
	s.step(30)
	assert_false(inv.world.items.has(spanner), "held 1 s: picked up")
	var b: HandsAndBelt = W.belt(s, ann.entity_id)
	assert_eq(b.slots[0].kind, ItemKinds.Kind.SPANNER)
	assert_eq(_kinds_in_slots(ann.connection.inventory), [ItemKinds.Kind.SPANNER, 0, 0, 0] as Array[int], "the owner's client has its belt")
	assert_eq(_kinds_in_slots(bob.connection.inventory), [0, 0, 0, 0] as Array[int], "bob's client has only his own belt")
	# A lamp picked up goes to the hand; bob sees it in her hand, never the spanner on her belt.
	W.put(s, ItemKinds.Kind.GAUZE_LAMP, a + Vector2i(1, 0))
	s.step(2)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 22)
	s.step(30)
	assert_eq(b.lamp_hand.kind, ItemKinds.Kind.GAUZE_LAMP)
	var seen_in_hand: Array[int] = []
	for raw: Variant in bob.connection.view.entities.values():
		var e: Dictionary = Variants.dict(raw)
		if e.has("in_hand"):
			seen_in_hand.append(int(Variants.number(e["in_hand"])))
	assert_eq(seen_in_hand, [ItemKinds.Kind.GAUZE_LAMP] as Array[int], "bob sees the lamp in her hand, nothing of her belt")
	# Set down: the lamp hand acts first, onto the faced tile.
	ann.at(s.run.tick).hold(InputRecord.HOLD_SET_DOWN, 22)
	s.step(30)
	assert_null(b.lamp_hand)
	var lamp_on_floor: Array[int] = []
	for raw: Variant in inv.world.items.keys():
		if inv.world.items[raw].kind == ItemKinds.Kind.GAUZE_LAMP:
			lamp_on_floor.append(int(Variants.number(raw)))
	assert_eq(lamp_on_floor.size(), 1)
	assert_eq(s.run.registry.get_entity(lamp_on_floor[0]).tile(), a + Vector2i(1, 0), "on the faced tile")
	# A lamp in a slot swaps with the lamp hand on Use.
	assert_true(inv.give(s.run, ann.entity_id, inv.world.make(ItemKinds.Kind.ELECTRIC_LAMP)))
	assert_eq(b.lamp_hand.kind, ItemKinds.Kind.ELECTRIC_LAMP)
	b.slots[1] = inv.world.make(ItemKinds.Kind.GAUZE_LAMP)
	ann.at(s.run.tick).select_slot(1).hold(InputRecord.HOLD_USE, 6)
	s.step(12)
	assert_eq(b.lamp_hand.kind, ItemKinds.Kind.GAUZE_LAMP, "using its slot swaps the lamps (0.2 s, MNR-06)")
	assert_eq(b.slots[1].kind, ItemKinds.Kind.ELECTRIC_LAMP)


func test_unseen_unfelt_is_refused() -> void:
	var s: Scenario = make({"seed": 12, "fixture": W.room()})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var inv: InventorySystem = s.run.inventory
	var spanner: int = W.put(s, ItemKinds.Kind.SPANNER, a + Vector2i(1, 0))
	ann.at(s.run.tick).face(0.0)
	s.step(4)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 30)
	s.step(40)
	assert_true(inv.world.items.has(spanner), "dark and unfelt: refused")
	inv.targets.note_felt(ann.entity_id, spanner)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 30)
	s.step(40)
	assert_false(inv.world.items.has(spanner), "felt: interacting again picks it up")
