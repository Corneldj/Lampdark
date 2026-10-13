extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-08 (§6.9): in a Fan surge the Tapper loses everything under 22 np: it ignores a 20 np bell
## and hears a 24 np engine beat.

const T = preload("res://tests/scenario/creatures/tapper_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_surge() -> void:
	var s: Scenario = make({"seed": 23, "fixture": T.road()})
	var h: TapperHearing = T.ears(s)
	h.fan_surge = func() -> bool: return true
	s.run.noise.emit(NoiseTypes.Type.PHONE_BELL, Vector2i(4, 2), {"level_np": 20.0})
	assert_eq(T.heard_now(s, h), 0, "a 20 np bell is lost in the surge")
	s.run.noise.emit(NoiseTypes.Type.ENGINE_RUNNING, Vector2i(4, 2), {"level_np": 24.0})
	assert_eq(T.heard_now(s, h), 1, "a 24 np engine beat is heard")
	h.fan_surge = func() -> bool: return false
	s.run.noise.emit(NoiseTypes.Type.PHONE_BELL, Vector2i(4, 2), {"level_np": 20.0})
	assert_eq(T.heard_now(s, h), 1, "after the surge the bell is heard")
