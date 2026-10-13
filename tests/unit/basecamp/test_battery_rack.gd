extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-01: the battery rack refuses before Power; after it, it charges a lamp from empty to full in
## 120 s, two slots.

const C = preload("res://tests/scenario/basecamp/camp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_rack() -> void:
	var s: Scenario = make({"seed": 6, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	assert_false(camp.rack.put(camp.powered, 0, 0.0), "dead until Power")
	camp.powered = true
	assert_true(camp.rack.put(camp.powered, 0, 0.0))
	assert_true(camp.rack.put(camp.powered, 1, 0.5))
	assert_false(camp.rack.put(camp.powered, 2, 0.0), "two slots")
	s.step(2399)
	assert_lt(Variants.number(camp.rack.slots[0]), 1.0, "not yet full at 119.95 s")
	s.step(1)
	assert_almost_eq(Variants.number(camp.rack.slots[0]), 1.0, 1e-9, "full at 120 s from empty")
	assert_eq(camp.rack.take(0), 1.0)
