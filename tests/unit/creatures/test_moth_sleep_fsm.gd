extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-03's state shell: spawned asleep at its roost as a motionless heap; a stir lasts 30 ticks
## with its tell; settling 60; preening 100 at the roost reached; feeling reports a heap and
## changes nothing; wake() from the engine and the hatch; nothing while retreating.

const W = preload("res://tests/scenario/creatures/moth_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_spawned_asleep() -> void:
	var s: Scenario = make({"seed": 1, "fixture": W.road()})
	var m: Moth = W.moth(s)
	s.step(1)
	assert_eq(m.state.name, &"asleep")
	assert_eq(m.roost, W.ROOST)
	assert_true(s.run.registry.get_entity(m.entity_id).flags & SimEntity.FLAG_MOTIONLESS != 0, "one more heap")
	assert_false(m.state.fills_cap_place)
	assert_eq(s.run.creatures.log.of_type(&"tell").size(), 0, "silent")


func test_stir_settle_preen_timings() -> void:
	var s: Scenario = make({"seed": 2, "fixture": W.road()})
	var m: Moth = W.moth(s)
	W.light_on(s, 0.35, 22)
	var asleep_for: int = W.until_not(s, m, &"asleep")
	assert_eq(m.state.name, &"stirring")
	assert_true(m.tell_active(), "the tell plays through the stir")
	var stirred: int = W.until_not(s, m, &"stirring")
	assert_eq(stirred, 30, "a stir lasts 30 ticks")
	assert_eq(m.state.name, &"settling", "no light left: it settles")
	assert_false(m.tell_active())
	var settled: int = W.until_not(s, m, &"settling")
	assert_eq(settled, 60, "settling lasts 60 ticks")
	assert_eq(m.state.name, &"asleep")
	gut.p("stirred after %d ticks of light" % asleep_for)
	# Begun between ticks (CRT-04 begins it inside one), so the count includes the tick that ends it.
	m.begin_preen(s.run)
	var preened: int = W.until_not(s, m, &"preening")
	assert_eq(preened - 1, 100, "preening lasts 100 ticks")
	assert_eq(m.state.name, &"asleep")
	assert_eq(m.roost, W.ROOST, "it sleeps where it reached")


func test_feeling_is_a_heap() -> void:
	var s: Scenario = make({"seed": 3, "fixture": W.road()})
	var m: Moth = W.moth(s)
	s.step(1)
	assert_eq(m.feel_reply(), "[a heap of coats]")
	assert_eq(m.state.name, &"asleep", "feeling changes nothing")


func test_engine_and_hatch() -> void:
	var s: Scenario = make({"seed": 4, "fixture": W.road()})
	var m: Moth = W.moth(s)
	s.step(1)
	assert_true(m.wake(s.run, MothSleep.Cause.ENGINE, Vector2(40.5, 2.5)))
	assert_eq(W.until_not(s, m, &"stirring") - 1, 30, "a 30-tick stir (begun between ticks; LFT-09 calls it inside one)")
	assert_eq(m.state.name, &"prowl", "the engine: Prowl toward base camp")
	assert_eq(m.rose_for, "engine")
	var s2: Scenario = make({"seed": 5, "fixture": W.road()})
	var m2: Moth = W.moth(s2)
	s2.step(1)
	m2.wake(s2.run, MothSleep.Cause.HATCH, Vector2(20.5, 2.5))
	W.until_not(s2, m2, &"stirring")
	assert_eq(m2.state.name, &"frenzy", "a hatch: Frenzy")
	var at: Vector2 = m2.waker["position"]
	assert_eq(at, Vector2(20.5, 2.5), "toward the hatch")
	var s3: Scenario = make({"seed": 6, "fixture": W.road()})
	var m3: Moth = W.moth(s3)
	s3.step(1)
	m3.retreat_until = s3.run.tick + 100
	assert_false(m3.wake(s3.run, MothSleep.Cause.ENGINE, Vector2.ZERO), "ignored in a retreat's deep sleep")
