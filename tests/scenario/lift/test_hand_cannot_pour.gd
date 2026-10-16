extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-06 (Gameplay §13.9): a Hired Hand may carry a can, but never pours. Its interact at the filler
## is refused, the tank and the can untouched; the same miner, a player again, pours.

const T = preload("res://tests/unit/lift/tank_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_hand_never_pours() -> void:
	var s: Scenario = make({"seed": 6301, "fixture": T.C.scenario_fixture()})
	T.camp(s, RepairList.Kind.STANDARD)
	var cid: MinerHandle = T.at_filler(s, "cid")
	var hands: Array[bool] = [true]
	s.run.crew.is_hand_driven = func(e: int) -> bool: return hands[0] and e == cid.entity_id
	var can: Item = T.can_in_hand(s, cid)
	T.hold(s, cid, 80)
	assert_eq(s.run.fuel.level_ticks, 0, "nothing poured")
	assert_eq(LampOil.oil_in(can), 4.0, "the can untouched")
	assert_eq(str(s.run.fuel.refused.back()["why"]), "a Hand")
	assert_false(s.run.inventory.actions.has(cid.entity_id), "no pour begun")
	hands[0] = false
	T.hold(s, cid, 66)
	assert_eq(s.run.fuel.level_ticks, FuelTank.unit_ticks(), "a player pours")
