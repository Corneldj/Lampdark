extends "res://tests/scenario/kit/scenario_test.gd"
## SND-03 (GDD §14.2): base camp sounds like shelter. A road event reaching Ann inside base camp
## through the shut west gate arrives 12 np further down than through the open gate, flagged
## muffled, and her client plays it through the low-passed Muffled bus.

const C = preload("res://tests/scenario/basecamp/camp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _heard(shut: bool) -> Dictionary:
	var s: Scenario = make({"seed": 111, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	var west: Gate = camp.gate_system.gate("west")
	C.shut_all(s, false)
	s.run.mine.native.set_barrier(Vector2i.ZERO, west.barrier, not shut)
	var ann: MinerHandle = s.add_miner("ann", west.middle() - west.outward * 3)
	s.step(3)
	s.run.noise.emit(NoiseTypes.Type.SHOT, west.middle() + west.outward * 6, {})
	s.step(4)
	for e: Dictionary in ann.connection.events:
		if int(Variants.number(e["type"])) == NoiseTypes.Type.SHOT:
			return e
	return {}


func test_twelve_down_and_muffled() -> void:
	var open: Dictionary = _heard(false)
	var shut: Dictionary = _heard(true)
	assert_false(open.is_empty(), "heard through the open gate")
	assert_false(shut.is_empty(), "and through the shut one")
	if open.is_empty() or shut.is_empty():
		return
	assert_eq(int(Variants.number(open["flags"])) & AudioRecord.MUFFLED, 0, "open: clear")
	assert_eq(int(Variants.number(shut["flags"])) & AudioRecord.MUFFLED, AudioRecord.MUFFLED, "shut: muffled")
	assert_almost_eq(float(Variants.number(open["remaining_np"])) - float(Variants.number(shut["remaining_np"])),
		Tuning.f(&"noise.closed_portal_cost"), 0.5, "12 np down")
	assert_eq(EventPlayer.bus_for(AudioRecord.from_event(shut)), "Muffled", "played low-passed")
