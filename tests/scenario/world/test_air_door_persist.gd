extends "res://tests/scenario/kit/scenario_test.gd"
## GEN-15 (Gameplay §12.6): a door's state survives its cell's eviction and return; the record is
## kept by door and put back when the cell loads.

const W = preload("res://tests/unit/world/door_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_open_door_comes_back_open() -> void:
	var s: Scenario = make({"seed": 9, "fixture": W.corridor()})
	s.step(1)
	var d: AirDoorSystem.Door = W.door(s)
	var cell: Vector2i = d.cell
	s.run.air_doors._flip(s.run, d, true)
	var key: String = d.key()
	s.mine.native.unload(cell)
	assert_false(s.run.air_doors.doors.has(key), "evicted with its cell")
	assert_true(Variants.flag(s.run.air_doors.states[key]), "but its state is kept")
	assert_true(s.fixture.load_into(s.mine) > 0, "the cell returns (as generated: shut)")
	assert_true(s.run.air_doors.doors.has(key))
	assert_true(W.door(s).open, "and the door is put back open")
	assert_true(s.mine.native.is_walkable(W.DOOR))
