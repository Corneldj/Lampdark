extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-08: only base camp's battery rack charges an electric lamp: anything else is refused (an
## error in debug builds); a charge clamps at full; with LFT-01's rack stub, empty to full takes
## 2,400 ticks (basecamp.battery_rack_full_charge_s).

const C = preload("res://tests/unit/mnr/chalk_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_only_the_rack_charges_and_it_clamps() -> void:
	var s: Scenario = make({"seed": 1111, "fixture": C.B.room()})
	s.step(1)
	var it: Item = ElectricLamps.make(s.run, 0)
	assert_false(s.run.electric.charge(s.run, it, 10.0, RefCounted.new()), "not the rack: refused")
	assert_push_error("only base camp's battery rack")
	assert_eq(ElectricLamps.battery_ticks(it), 0)
	var rack: BatteryRack = BatteryRack.new()
	assert_true(s.run.electric.charge(s.run, it, 9999.0, rack))
	assert_eq(ElectricLamps.battery_ticks(it), ElectricLamps.full_ticks(), "clamped at full")


func test_the_rack_stub_fills_it_in_2400_ticks() -> void:
	var s: Scenario = make({"seed": 1112, "fixture": C.B.room()})
	s.step(1)
	var it: Item = ElectricLamps.make(s.run, 0)
	var rack: BatteryRack = BatteryRack.new()
	var full_s: float = Tuning.f(&"basecamp.battery_rack_full_charge_s")
	var hz: float = Tuning.f(&"net.tick_hz")
	assert_eq(roundi(full_s * hz), 2400, "2 minutes")
	var per_tick: float = Tuning.f(&"lamp.electric_battery") / (full_s * hz)
	var ticks: int = 0
	while ElectricLamps.battery_ticks(it) < ElectricLamps.full_ticks() and ticks < 3000:
		s.run.electric.charge(s.run, it, per_tick, rack)
		ticks += 1
	assert_eq(ticks, 2400, "empty to full in 2,400 ticks")
