extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-08: within 10 tiles of the Stythe's tell (a stand-in until CRT-14) Ann's wick-up lamp
## gutters: her own block reports the radius x0.7 and GUTTER, the core falls from 3.3 to 2.31 tiles,
## and tiles beyond 3.85 tiles go dark on the grid. It recovers when the tell ends.

const FW = preload("res://tests/scenario/vis/flame_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_core_falls_to_231() -> void:
	var s: Scenario = make({"seed": 63, "fixture": FW.hall(40)})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(10, 3))
	ann.at(0).lamp(false, LampRules.WICK_UP)
	s.step(1)
	L.lit_in_hand(s, ann, LampRules.WICK_UP)
	s.step(6)
	var core: float = Tuning.f(&"light.core_fraction")
	var r: float = float(Variants.number(ann.connection.view.own["lamp_radius"]))
	assert_almost_eq(r * core, 3.3, 0.04, "a wick-up core: 3.3 tiles")
	var probe: Vector2i = Vector2i(15, 3)
	assert_gt(s.run.light.grid.value(probe), 0)
	var active: Array[bool] = [true]
	FW.stythe(s, Vector2(19.5, 3.5), active)
	s.step(4)
	var own: Dictionary = ann.connection.view.own
	assert_eq(int(Variants.number(own["flame"])) & FlameFlags.GUTTER, FlameFlags.GUTTER, "guttering")
	assert_almost_eq(float(Variants.number(own["lamp_radius"])) * core, 2.31, 0.04, "the core: 2.31 tiles")
	assert_eq(s.run.light.grid.value(probe), 0, "5 tiles off: dark now")
	active[0] = false
	s.step(4)
	assert_almost_eq(float(Variants.number(ann.connection.view.own["lamp_radius"])) * core, 3.3, 0.04, "back")
	assert_eq(int(Variants.number(ann.connection.view.own["flame"])), 0)
