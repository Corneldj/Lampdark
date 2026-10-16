extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-06: the paraffin tank. Its capacity is the list's cans (12,000, 24,000 and 36,000 burn ticks);
## a full can takes 60 ticks of held interact at the filler and adds one tank unit, and an early
## release, a move or a state change adds nothing; a 3-fill can adds 3 fills, a 4-fill can into 2
## fills of space moves 2 and keeps 2, and a full tank, a dry can or no can is refused. Fuel is done
## the first time the tank is full, and the burn never clears it; a full Standard tank burns for
## exactly 20 minutes and each can poured adds 5; the sight glass carries a mark per can and the
## paraffin's line, never a number on screen.

const T = preload("res://tests/unit/lift/tank_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _world(run_seed: int, kind: RepairList.Kind = RepairList.Kind.STANDARD) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": T.C.scenario_fixture()})
	T.camp(s, kind)
	var ann: MinerHandle = T.at_filler(s, "ann")
	return [s, ann]


func test_capacity_is_the_lists_cans_in_burn_ticks() -> void:
	var w: Array = _world(6001)
	var s: Scenario = w[0]
	assert_eq(FuelTank.unit_ticks(), 6000, "a can runs the engine 5 minutes")
	assert_eq(FuelTank.fill_ticks(), 1500, "a lamp fill is a quarter of it")
	var caps: Array[int] = []
	for kind: RepairList.Kind in [RepairList.Kind.SHORT, RepairList.Kind.STANDARD, RepairList.Kind.FULL]:
		s.run.repair.set_list(RepairList.for_run(6001, kind, false))
		caps.append(s.run.fuel.capacity_ticks(s.run))
	assert_eq(caps, [12000, 24000, 36000] as Array[int])


func test_a_full_can_takes_3_s_and_adds_one_tank_unit() -> void:
	var w: Array = _world(6002)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var can: Item = T.can_in_hand(s, ann)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 80)
	assert_true(s.run_until(func(sc: Scenario) -> bool: return sc.run.inventory.actions.has(ann.entity_id), 20), "the pour starts")
	var a: TimedAction = s.run.inventory.actions[ann.entity_id]
	assert_eq(a.verb, &"pour_fuel")
	assert_eq(a.ticks_needed, 60, "3 s")
	s.step(70)
	assert_eq(s.run.fuel.level_ticks, 6000, "one tank unit")
	assert_eq(LampOil.oil_in(can), 0.0, "the can poured dry")
	var poured: Dictionary = s.run.fuel.pours[0]
	assert_eq(int(Variants.number(poured["tick"])) - a.started_tick, 60, "after 60 ticks of holding")


func test_an_early_release_a_move_or_a_state_change_adds_nothing() -> void:
	for case: String in ["released", "moved", "caught"]:
		var w: Array = _world(6010 + case.length())
		var s: Scenario = w[0]
		var ann: MinerHandle = w[1]
		var can: Item = T.can_in_hand(s, ann)
		ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 30 if case == "released" else 90)
		s.step(20)
		match case:
			"moved":
				ann.at(s.run.tick).move(0.0, InputRecord.Gait.WALK, 3)
			"caught":
				s.run.miner_state.enter_caught(ann.entity_id, &"man_trap", 1)
		s.step(80)
		assert_eq(s.run.fuel.level_ticks, 0, "%s: nothing in the tank" % case)
		assert_eq(LampOil.oil_in(can), 4.0, "%s: nothing out of the can" % case)


func test_part_cans_pour_their_fills_up_to_the_brim() -> void:
	var w: Array = _world(6020, RepairList.Kind.SHORT)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var three: Item = T.can_in_hand(s, ann, 3.0)
	T.hold(s, ann, 66)
	assert_eq(s.run.fuel.level_ticks, 4500, "a 3-fill can adds 3 fills")
	assert_eq(LampOil.oil_in(three), 0.0)
	var full: Item = T.can_in_hand(s, ann)
	T.hold(s, ann, 66)
	assert_eq(s.run.fuel.capacity_ticks(s.run) - s.run.fuel.level_ticks, 1500, "a fill of space left")
	assert_eq(LampOil.oil_in(full), 0.0)
	s.run.fuel.consume_ticks(1500)
	var two_left: Item = T.can_in_hand(s, ann)
	T.hold(s, ann, 66)
	assert_true(s.run.fuel.is_full(s.run), "two fills of space: it takes two")
	assert_eq(LampOil.oil_in(two_left), 2.0, "and the can keeps two")
	# A full tank, a dry can and an empty hand are refused, nothing started.
	T.hold(s, ann, 10)
	assert_eq(str(s.run.fuel.refused.back()["why"]), "full")
	s.run.fuel.consume_ticks(3000)
	T.can_in_hand(s, ann, 0.0)
	T.hold(s, ann, 10)
	assert_eq(str(s.run.fuel.refused.back()["why"]), "a dry can")
	s.run.inventory.hands_of(ann.entity_id).free_hand = null
	T.hold(s, ann, 10)
	assert_eq(str(s.run.fuel.refused.back()["why"]), "no can")


func test_fuel_is_done_the_first_time_it_is_full_and_stays_done() -> void:
	var w: Array = _world(6030, RepairList.Kind.SHORT)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var firsts: Array[int] = [0]
	s.run.fuel.filled_first_time.connect(func() -> void: firsts[0] += 1)
	T.can_in_hand(s, ann)
	T.hold(s, ann, 66)
	assert_false(s.run.repair.is_done(&"fuel"), "half full: not yet")
	T.can_in_hand(s, ann)
	T.hold(s, ann, 66)
	assert_true(s.run.fuel.done)
	assert_true(s.run.repair.is_done(&"fuel"), "LFT-03's Fuel job done")
	s.run.fuel.consume_ticks(9000)
	assert_true(s.run.fuel.done, "burning never clears it")
	T.can_in_hand(s, ann)
	T.hold(s, ann, 66)
	assert_eq(s.run.fuel.level_ticks, 9000, "topped up")
	assert_eq(firsts[0], 1, "full the first time once")
	assert_true(s.run.fuel.is_fuelled())


func test_a_full_standard_tank_burns_20_minutes_and_each_can_adds_5() -> void:
	var w: Array = _world(6040)
	var s: Scenario = w[0]
	var tank: FuelTank = s.run.fuel
	tank.level_ticks = tank.capacity_ticks(s.run)
	var emptied: Array[int] = [0]
	tank.emptied.connect(func() -> void: emptied[0] += 1)
	var ran: int = 0
	while tank.consume_ticks(1) == 1:
		ran += 1
	assert_eq(ran, 20 * 60 * 20, "20 minutes of running at 20 Hz")
	assert_eq(emptied[0], 1, "emptied once")
	assert_true(tank.is_empty())
	tank.level_ticks = 0
	var can: Item = s.run.inventory.world.make(ItemKinds.Kind.PARAFFIN_CAN, 1, {"fills": 4.0})
	assert_eq(tank.pour(s.run, 0, can), 4.0)
	assert_eq(tank.level_ticks, 5 * 60 * 20, "a can: 5 more minutes")


func test_the_sight_glass_shows_marks_and_a_line_never_a_number() -> void:
	var w: Array = _world(6050)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var tank: FuelTank = s.run.fuel
	assert_ne(tank.glass, 0, "a glass at the filler")
	assert_eq(s.run.registry.get_entity(tank.glass).kind, WorldIds.EntityKind.FIXTURE)
	T.can_in_hand(s, ann, 3.0)
	T.hold(s, ann, 66)
	var bits: int = tank.glass_bits(s.run)
	assert_eq(FixtureKinds.kind_of(bits), FixtureKinds.Kind.TANK_GLASS)
	assert_eq(FixtureKinds.read_tank_glass(bits), {"cans": 4, "fills": 3}, "four marks, the line at three fills")
	assert_eq(s.run.base_camp.run_start_check(s.run), [] as Array[String], "the glass belongs in base camp")
