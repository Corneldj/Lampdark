extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-14: the tell plays only in Hunt, WindUp, Drag and Collect: flames within 10 tiles gutter
## (shuttered ones too), the breath sounds all around, SND-08's crackle and VIS-10's bite read it;
## lurking or circling, none of it.

const H = preload("res://tests/scenario/creatures/stythe_hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_only_in_the_active_states() -> void:
	var s: Scenario = make({"seed": 1451, "fixture": H.road(), "overrides": H.W.ON})
	var h: H = H.new()
	h.build(s)
	h.pulls.clear()
	var near: GauzeLamp = s.run.lamps.create(s.run, 1.0, 0, true, LampRules.WICK_NORMAL, Vector2(48.5, 2.5))
	var far: GauzeLamp = s.run.lamps.create(s.run, 1.0, 0, true, LampRules.WICK_NORMAL, Vector2(55.5, 2.5))
	s.step(2)
	s.run.lamps.shutter_in_place(s.run, near, 0)
	s.run.lamps.shutter_in_place(s.run, far, 0)
	s.step(4)
	for state: StringName in [&"lurk", &"circle", &"hunt", &"windup", &"drag", &"collect", &"check"]:
		h.st.enter(s.run, state, "test")
		var active: bool = [&"hunt", &"windup", &"drag", &"collect"].has(state)
		assert_eq(h.st.tell_active(), active, "%s: the tell" % state)
		assert_eq(h.st.flame_tell(), FlameFlags.GUTTER if active else 0, "%s: the gutter" % state)
		var crackle: Array = s.run.voice.conditions.stythe_tells.call()
		var bite: Array = s.run.vision.bite_sources.call(s.run)
		assert_eq(crackle.size(), 1 if active else 0, "%s: the crackle" % state)
		assert_eq(bite.size(), 1 if active else 0, "%s: the bite" % state)
		var tells: int = 0
		for t: Tell in s.run.creatures.tells:
			if t.creature == h.st:
				tells += 1
		assert_eq(tells, 1 if active else 0, "%s: the breath" % state)
	h.st.enter(s.run, &"windup", "test")
	s.step(2)
	assert_eq(s.run.flame_states.flags_of(near.source) & FlameFlags.GUTTER, FlameFlags.GUTTER, "a shuttered flame 8 tiles off gutters")
	assert_eq(s.run.flame_states.flags_of(far.source) & FlameFlags.GUTTER, 0, "not one 15 tiles off")
