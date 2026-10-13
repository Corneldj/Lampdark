extends "res://tests/scenario/kit/scenario_test.gd"
## GEN-15 with CRT-02 (Gameplay §7.2): the Moth at a shut air door waits 3 s (60 ticks), crosses,
## and the door never reads open: no light crosses it at any tick.

const W = preload("res://tests/unit/world/door_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_held_three_seconds_and_never_open() -> void:
	var s: Scenario = make({"seed": 8, "fixture": W.corridor()})
	s.run.lamps.create(s.run, 1.0, 3, true, LampRules.WICK_UP, Vector2(13.5, 1.5))
	assert_ne(s.place_stand_in(WorldIds.EntityKind.MOTH, Vector2i(8, 1)), 0)
	var moth: KitCreature = s.run.creatures.creature_of_kind(WorldIds.EntityKind.MOTH)
	moth.follower = NavFollower.new()
	moth.speed = 2.5
	moth.follower.go(s.run, s.run.creatures.nav, moth, Vector2i(22, 1), NavModes.Mode.WALKER)
	var n: Dictionary = {"held": 0, "leaked": 0, "opened": 0}
	s.on_tick = func(sc: Scenario) -> void:
		if moth.follower.status == NavFollower.Status.HOLDING:
			n["held"] = int(Variants.number(n["held"])) + 1
		if W.door(sc).open:
			n["opened"] = int(Variants.number(n["opened"])) + 1
		if sc.run.light.light_at(Vector2i(16, 1)) > 0.0:
			n["leaked"] = int(Variants.number(n["leaked"])) + 1
	s.step(200)
	assert_eq(int(Variants.number(n["held"])), roundi(Tuning.f(&"moth.air_door_hold_s") * Tuning.f(&"net.tick_hz")), "held 60 ticks")
	assert_eq(moth.follower.status, NavFollower.Status.ARRIVED, "then it crossed")
	assert_eq(int(Variants.number(n["opened"])), 0, "the door never read open")
	assert_eq(int(Variants.number(n["leaked"])), 0, "and no light crossed it")
