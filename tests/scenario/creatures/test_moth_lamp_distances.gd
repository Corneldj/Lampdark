extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-03's light table (VIS-02's values): the distances at which each lamp puts 0.30 (the clock
## runs) and 0.60 (it wakes) on a heap, within +/-0.05 tiles; a wick-down lamp at 2 tiles puts
## 0.21; two normal lamps 2.5 tiles off start the clock and one alone does not.

const W = preload("res://tests/scenario/creatures/moth_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _light(d: float, radius: float) -> float:
	return LbLightMath.falloff_milli(d, radius, 1.0, Tuning.f(&"light.core_fraction"), Tuning.f(&"light.core_value"),
		Tuning.f(&"light.edge_value")) / 1000.0


## The farthest distance at which the light is still `level` or more.
func _reach(radius: float, level: float) -> float:
	var lo: float = 0.0
	var hi: float = radius
	for i: int in 60:
		var mid: float = (lo + hi) * 0.5
		if _light(mid, radius) >= level:
			lo = mid
		else:
			hi = mid
	return lo


func test_table() -> void:
	var rows: Array = [
		["wick down", Tuning.f(&"lamp.radius_wick_down"), 1.5, 0.9],
		["a candle", Tuning.f(&"items.candle_radius"), 1.5, 0.9],
		["a belt hook", Tuning.f(&"lamp.hook_radius"), 1.5, 0.9],
		["normal", Tuning.f(&"lamp.radius_normal"), 2.4, 1.4],
		["wick up", Tuning.f(&"lamp.radius_wick_up"), 3.3, 1.9],
	]
	for r: Array in rows:
		var name: String = r[0]
		var radius: float = r[1]
		var at_030: float = _reach(radius, 0.30)
		var at_060: float = _reach(radius, 0.60)
		gut.p("%s (R %.1f): 0.30 within %.2f, 0.60 within %.2f" % [name, radius, at_030, at_060])
		assert_almost_eq(at_030, Variants.number(r[2]), 0.05, "%s: 0.30" % name)
		assert_almost_eq(at_060, Variants.number(r[3]), 0.05, "%s: 0.60" % name)
	assert_almost_eq(_light(2.0, Tuning.f(&"lamp.radius_wick_down")), 0.21, 0.01, "wick down at 2 tiles: a shape, never a face")


func _two_lamps(both: bool) -> StringName:
	var s: Scenario = make({"seed": 16, "fixture": W.road()})
	var m: Moth = W.moth(s)
	var centre: Vector2 = Vector2(W.ROOST) + Vector2(0.5, 0.5)
	var r: float = Tuning.f(&"lamp.radius_normal")
	s.run.light.grid.add_point("gauze_lamp", 1, 0, 0, r, 1.0, centre - Vector2(2.5, 0.0), 0)
	if both:
		s.run.light.grid.add_point("gauze_lamp", 1, 0, 0, r, 1.0, centre + Vector2(2.5, 0.0), 0)
	s.step(2)
	gut.p("%s: %.2f on the Moth" % ["two normal lamps 2.5 off" if both else "one", s.run.light.light_at(W.ROOST)])
	s.step(30)
	return m.state.name


func test_two_lamps_add() -> void:
	assert_eq(_two_lamps(false), &"asleep", "one normal lamp 2.5 tiles off: 0.29, nothing")
	assert_ne(_two_lamps(true), &"asleep", "two: 0.58, the clock runs and it stirs")
