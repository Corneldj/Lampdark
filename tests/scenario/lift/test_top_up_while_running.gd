extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-06 with the burn: a full Standard tank runs 20 minutes, and a can poured while it runs adds
## 5 more: 25 minutes in all, Fuel staying done throughout. LFT-08's engine is stood in for by a
## burner taking FuelTank.consume_ticks each tick, 50 burn ticks a tick, so 25 minutes pass in 600.

const T = preload("res://tests/unit/lift/tank_world.gd")
const SPEED: int = 50


## LFT-08's burn until it lands: SPEED burn ticks every tick while the tank has any.
class Burner:
	extends SimSystem
	var ran: int = 0

	func stage() -> int:
		return StageTable.Stage.WORLD

	func order() -> int:
		return 37

	func system_name() -> String:
		return "test_burner"

	func tick(run: RunState) -> void:
		ran += run.fuel.consume_ticks(SPEED)


func test_a_can_poured_while_running_adds_5_minutes() -> void:
	var s: Scenario = make({"seed": 6201, "fixture": T.C.scenario_fixture()})
	T.camp(s, RepairList.Kind.STANDARD)
	var ann: MinerHandle = T.at_filler(s, "ann")
	var tank: FuelTank = s.run.fuel
	for i: int in 4:
		T.can_in_hand(s, ann)
		T.hold(s, ann, 66)
	assert_true(tank.done, "full: Fuel done")
	var burner: Burner = Burner.new()
	s.run.add_system(burner)
	s.step(100)
	assert_lt(tank.level_ticks, tank.capacity_ticks(s.run), "running")
	T.can_in_hand(s, ann)
	T.hold(s, ann, 66)
	assert_eq(tank.pours.size(), 5, "topped up while running")
	assert_true(s.run_until(func(_sc: Scenario) -> bool: return tank.is_empty(), 1200), "ran dry")
	assert_eq(burner.ran, (20 + 5) * 60 * 20, "20 minutes from full, and 5 more for the can")
	assert_true(tank.done, "running dry never clears Fuel")
	assert_false(tank.is_fuelled(), "but a dry tank fuels nothing")
