extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-05: a lit lamp passes to a lampless miner in 1 s through the ring; it arrives open in his empty
## lamp hand, and its light source follows him.

const W = preload("res://tests/unit/mnr/belt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")
const R = preload("res://tests/unit/mnr/ring_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_hand_over_lamp() -> void:
	var s: Scenario = make({"seed": 1, "fixture": W.room()})
	var pair: Array = R.pair(s, false)
	var ann: MinerHandle = pair[0]
	var bob: MinerHandle = pair[1]
	var lamp: GauzeLamp = L.lit_in_hand(s, ann, LampRules.WICK_UP)
	s.step(4)
	assert_gt(s.run.light.grid.owned_radius(ann.entity_id), 0.0)
	R.tap(s, ann)
	assert_true(Variants.array(ann.connection.ring.get("options", [])).has("hand_over"))
	assert_true(R.pick_and_hold(s, ann, "hand_over", 25))
	assert_eq(s.run.inventory.hands_of(bob.entity_id).lamp_hand, lamp.item, "in his lamp hand")
	assert_eq(lamp.holder, bob.entity_id)
	assert_eq(lamp.state(), GauzeLamp.State.OPEN, "burning, open as it was")
	assert_eq(lamp.wick, LampRules.WICK_UP)
	s.step(2)
	assert_almost_eq(s.run.light.grid.owned_radius(bob.entity_id), 5.5, 1e-6, "the light follows him")
	assert_eq(s.run.light.grid.owned_radius(ann.entity_id), 0.0)
