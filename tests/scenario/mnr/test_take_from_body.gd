extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-05 with RSC-01: the ring on a fallen miner offers taking from his belt; the belt list reaches
## only the taker; picking a slot and holding 1 s moves that item.

const W = preload("res://tests/unit/mnr/belt_world.gd")
const R = preload("res://tests/unit/mnr/ring_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_take() -> void:
	var s: Scenario = make({"seed": 2, "fixture": W.room()})
	var pair: Array = R.pair(s)
	var ann: MinerHandle = pair[0]
	var bob: MinerHandle = pair[1]
	var cy: MinerHandle = s.add_miner("cy", s.fixture.spot("b"))
	var inv: InventorySystem = s.run.inventory
	assert_true(inv.give(s.run, bob.entity_id, inv.world.make(ItemKinds.Kind.SPANNER)))
	assert_true(inv.give(s.run, bob.entity_id, inv.world.make(ItemKinds.Kind.HEALING_KIT)))
	s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.BLAST)
	s.step(4)
	R.tap(s, ann)
	var options: Array = Variants.array(ann.connection.ring.get("options", []))
	assert_true(options.has("take:0") and options.has("take:1"), "take is offered on a body")
	assert_false(options.has("hand_over"), "nothing for the standing")
	var belt: Array = Variants.array(ann.connection.ring["belt"])
	assert_eq(int(Variants.number(Variants.array(belt[1])[0])), ItemKinds.Kind.HEALING_KIT, "his belt list, to her")
	assert_true(bob.connection.ring.is_empty() and cy.connection.ring.is_empty(), "and to nobody else")
	assert_true(R.pick_and_hold(s, ann, "take:1", 25))
	assert_eq(inv.hands_of(ann.entity_id).slots[0].kind, ItemKinds.Kind.HEALING_KIT, "taken in 1 s")
	assert_null(inv.hands_of(bob.entity_id).slots[1])
	assert_eq(inv.hands_of(bob.entity_id).slots[0].kind, ItemKinds.Kind.SPANNER)
