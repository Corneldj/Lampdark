extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-07 (§10.7): normal lamps parked in rings 1, 2 and 3 go dry at 12:00, 9:36 and 8:00.

const W = preload("res://tests/unit/mnr/belt_world.gd")
const O = preload("res://tests/unit/mnr/oil_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_by_ring() -> void:
	var s: Scenario = make({"seed": 90, "fixture": W.room()})
	var want: Dictionary = {1: "12:00", 2: "9:36", 3: "8:00"}
	var lamps: Dictionary = {}
	for ring: int in [1, 2, 3]:
		lamps[ring] = O.parked(s, O.point_in_ring(ring), LampRules.WICK_NORMAL)
	var start: int = s.run.tick
	var dry: Dictionary = {}
	s.run.lamps.lamp_changed.connect(func(l: GauzeLamp, what: StringName, _c: String) -> void:
		if what == &"dry":
			dry[l.uid] = s.run.tick - start)
	O.run_server(s, 12 * 60 * 20 + 20)
	for ring: int in [1, 2, 3]:
		var l: GauzeLamp = lamps[ring]
		var ticks: int = int(Variants.number(dry.get(l.uid, -1)))
		var secs: int = roundi(ticks / 20.0)
		var clock: String = "%d:%02d" % [secs / 60, secs % 60]
		gut.p("ring %d: dry at %s (%d ticks)" % [ring, clock, ticks])
		assert_eq(clock, str(want[ring]), "ring %d" % ring)
