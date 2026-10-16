extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-06 (Gameplay §3.9, 24:40): paraffin is one store. On a Short list three cans balance exactly:
## one can fills four dry lamps (MNR-07), two fill the tank, and Fuel is done; the lamp can is dry
## and pours nothing. Had a lamp taken one fill from a tank can, the tank would stand a fill short.
## The crew sees the level only on the sight glass, lit: a mark per can and the paraffin's line.

const T = preload("res://tests/unit/lift/tank_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


## Dry lamps a tile behind `h` (she faces the filler, so her interact still finds it), each topped
## up from `can` by a held use (MNR-07's pour).
func _fill_lamps(s: Scenario, h: MinerHandle, can: Item, n: int) -> void:
	var me: Vector2 = s.run.registry.get_entity(h.entity_id).position
	var at: Vector2 = me - (s.run.fuel.filler - me).normalized()
	for i: int in n:
		var l: GauzeLamp = s.run.lamps.create(s.run, 0.0, 3, false, LampRules.WICK_NORMAL, at)
		h.at(s.run.tick).hold(InputRecord.HOLD_USE, 64)
		s.step(1)
		assert_true(s.run.inventory.start_action(s.run, LampOil.pour_action(s.run, h.entity_id, can, l)))
		s.step(66)
		assert_almost_eq(l.oil, 1.0, 1e-6, "lamp %d full" % i)


func test_three_cans_balance_exactly() -> void:
	var s: Scenario = make({"seed": 6101, "fixture": T.C.scenario_fixture()})
	T.camp(s, RepairList.Kind.SHORT)
	var ann: MinerHandle = T.at_filler(s, "ann")
	var lamp_can: Item = T.can_in_hand(s, ann)
	_fill_lamps(s, ann, lamp_can, 4)
	assert_eq(LampOil.oil_in(lamp_can), 0.0, "four lamp fills: a whole can")
	T.hold(s, ann, 10)
	assert_eq(str(s.run.fuel.refused.back()["why"]), "a dry can", "it pours nothing into the tank")
	for i: int in 2:
		T.can_in_hand(s, ann)
		T.hold(s, ann, 66)
	assert_true(s.run.fuel.is_full(s.run), "two cans fill a Short tank")
	assert_true(s.run.repair.is_done(&"fuel"))
	# The sight glass as the client sees it lit: a mark for each of two cans, the line at the top.
	var glass: Dictionary = {}
	for raw: Variant in ann.connection.view.entities.values():
		var e: Dictionary = raw
		if int(Variants.number(e.get("size_or_kind", 0))) == SeenKind.Kind.FIXTURE:
			glass = FixtureKinds.read_tank_glass(int(Variants.number(e.get("in_hand", 0))))
	assert_eq(glass, {"cans": 2, "fills": 8}, "the glass: two marks, full")


func test_a_fill_taken_for_a_lamp_leaves_the_tank_short() -> void:
	var s: Scenario = make({"seed": 6102, "fixture": T.C.scenario_fixture()})
	T.camp(s, RepairList.Kind.SHORT)
	var ann: MinerHandle = T.at_filler(s, "ann")
	var first: Item = T.can_in_hand(s, ann)
	_fill_lamps(s, ann, first, 1)
	assert_eq(LampOil.oil_in(first), 3.0)
	T.hold(s, ann, 66)
	T.can_in_hand(s, ann)
	T.hold(s, ann, 66)
	assert_eq(s.run.fuel.capacity_ticks(s.run) - s.run.fuel.level_ticks, FuelTank.fill_ticks(), "a fill short")
	assert_false(s.run.repair.is_done(&"fuel"), "so Fuel is not done")
