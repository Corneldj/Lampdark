extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-06 with MNR-04's two-handed actions: starting a carry hangs the open lamp on the belt hook
## at radius 2.5 whatever the wick; the hook's shutter still answers 'Douse!'; when the carry ends
## the lamp returns to the hand as it is.

const W = preload("res://tests/unit/mnr/belt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_hook_on_carry() -> void:
	var s: Scenario = make({"seed": 42, "fixture": W.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	ann.at(0).lamp(false, 2)
	s.step(2)
	var l: GauzeLamp = L.lit_in_hand(s, ann, LampRules.WICK_UP)
	s.step(2)
	assert_almost_eq(s.run.light.grid.owned_radius(ann.entity_id), 5.5, 1e-6)
	assert_true(s.run.inventory.begin_two_handed(s.run, ann.entity_id), "a carry starts (MNR-13 calls this)")
	s.step(2)
	assert_eq(l.state(), GauzeLamp.State.HOOKED)
	assert_almost_eq(s.run.light.grid.owned_radius(ann.entity_id), 2.5, 1e-6, "on the hook: 2.5 at wick up")
	ann.at(s.run.tick).lamp(true, 2)
	s.step(8)
	assert_eq(l.state(), GauzeLamp.State.HOOKED_SHUTTERED, "the hauler obeys 'Douse!'")
	assert_eq(s.run.light.grid.owned_radius(ann.entity_id), 0.0)
	s.run.inventory.end_two_handed(ann.entity_id)
	s.step(2)
	assert_eq(l.state(), GauzeLamp.State.SHUTTERED, "back in the hand, still shuttered")
	ann.at(s.run.tick).lamp(false, 2)
	s.step(8)
	assert_almost_eq(s.run.light.grid.owned_radius(ann.entity_id), 5.5, 1e-6, "opened: its wick is still up")
