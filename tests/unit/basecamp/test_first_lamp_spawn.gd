extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-01: at run creation, and never on resume, exactly one gauze lamp hangs on lamp_hook: one
## full fill, 3 notches, unlit; with the emergency lamps not flames, the mine holds no flame.

const C = preload("res://tests/scenario/basecamp/camp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_run_creation() -> void:
	var s: Scenario = make({"seed": 3, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s, 1, true)
	s.step(2)
	var lamp: FirstLamp = camp.first_lamp
	assert_not_null(lamp)
	var hook: Vector2i = Basecamp.fixture(C.SEED, "lamp_hook", 1)[0]["position"]
	assert_eq(lamp.hook, hook, "on the lamp hook")
	assert_eq(s.run.registry.get_entity(lamp.entity).position, Vector2(hook) + Vector2(0.5, 0.5))
	assert_eq(lamp.fills, 1, "one full fill")
	assert_eq(lamp.notches, 3, "three notches")
	assert_eq(lamp.wick, 1, "wick normal")
	assert_false(lamp.lit, "unlit")
	assert_eq(camp.flames_inside(s.run).size(), 0, "the emergency lamps are not flames")
	var big: Rect2 = Rect2(-200, -200, 400, 400)
	assert_eq(s.run.light.grid.flame_sources(big).size(), 0, "the only flame in the mine is unlit")


func test_never_on_resume() -> void:
	var s: Scenario = make({"seed": 4, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s, 0, false)
	assert_null(camp.first_lamp, "a resume hangs no new lamp")
