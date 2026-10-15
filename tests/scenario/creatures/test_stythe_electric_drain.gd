extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-13: an electric lamp loses 30 s of battery a snuff instead of going out: a full one (360 s)
## beside an active Stythe lasts 24 +/- 2 s, or 19 +/- 2 s in its territory. MNR-08's lamp is not
## built, so a stub battery stands in for it (the drain hook is the Stythe's).

const W = preload("res://tests/unit/creatures/stythe_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _lasts(territory: bool) -> float:
	var s: Scenario = make({"seed": 1271, "fixture": W.road(60), "overrides": W.ON})
	var st: StytheCreature = W.stythe(s, Vector2i(30, 2), Vector2i(30, 2) if territory else Vector2i(-5000, -5000))
	s.step(1)
	var at: Vector2 = st.position(s.run) + Vector2(2.5, 0.0)
	var source: int = s.run.light.grid.add_point(StytheSnuff.ELECTRIC_KIND, LbLightGrid.COLOUR_WHITE, 0, 0, 1.0, 1.0, at, 0)
	var battery: Array[float] = [Tuning.f(&"lamp.electric_battery")]
	st.snuff.electric_sources = func(_r: RunState) -> Array: return [source] if battery[0] > 0.0 else []
	st.electric_drain = func(_r: RunState, _s: int, seconds: float) -> bool:
		battery[0] -= seconds
		return true
	st.enter(s.run, &"windup", "test")  # an active state that holds still
	var ticks: int = 0
	while battery[0] > 0.0 and ticks < 2000:
		s.step(1)
		battery[0] -= 1.0 / 20.0
		ticks += 1
	return ticks / 20.0


func test_a_full_battery_beside_it() -> void:
	var out: float = _lasts(false)
	var inside: float = _lasts(true)
	gut.p("a full battery lasts %.1f s beside it, %.1f s in its territory" % [out, inside])
	assert_between(out, 22.0, 26.0, "24 +/- 2 s")
	assert_between(inside, 17.0, 21.0, "19 +/- 2 s in its territory")
