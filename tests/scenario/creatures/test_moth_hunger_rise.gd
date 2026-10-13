extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-03: hunger raises the Moth straight to Prowl 15-25 minutes after falling asleep (within 2
## minutes under Restless Moth), with no stir and no stirring tell (CRT-04's awake tell plays as it prowls).

const W = preload("res://tests/scenario/creatures/moth_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_hunger() -> void:
	var s: Scenario = make({"seed": 17, "fixture": W.road()})
	var m: Moth = W.moth(s)
	var after: int = m.sleep.hunger_at - s.run.tick
	assert_between(after, 900 * 20, 1500 * 20, "15-25 minutes")
	var states: Dictionary = {}
	s.on_tick = func(_sc: Scenario) -> void: states[m.state.name] = true
	s.step(after + 2)
	assert_eq(m.state.name, &"prowl")
	assert_eq(m.rose_for, "hunger")
	assert_false(states.has(&"stirring"), "no stir")
	var stir_tells: int = 0
	for e: Dictionary in s.run.creatures.log.of_type(&"tell"):
		if Variants.dict(e.get("fields", e)).get("kind", &"") == &"moth_stir":
			stir_tells += 1
	assert_eq(stir_tells, 0, "no stir tell, no rising rustle (CRT-04's awake tell plays while it prowls)")


func test_restless() -> void:
	var s: Scenario = make({"seed": 18, "fixture": W.road()})
	s.run.creatures.conditions = ["restless_moth"] as Array[String]
	var m: Moth = W.moth(s)
	var after: int = m.sleep.hunger_at - s.run.tick
	assert_lte(after, 120 * 20, "within 2 minutes")
	s.step(after + 2)
	assert_eq(m.state.name, &"prowl")
	for e: Dictionary in s.run.creatures.log.of_type(&"tell"):
		assert_ne(str(Variants.dict(e.get("fields", e)).get("kind", "")), "moth_stir", "no stir tell")
