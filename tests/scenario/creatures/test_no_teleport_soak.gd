extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-01: no creature moves more than its speed x 0.05 s (+0.01 tiles) in a tick, over a soak
## with wandering bots; a planted teleport is caught.

const W = preload("res://tests/scenario/creatures/creature_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_soak() -> void:
	var s: Scenario = make({"seed": 21, "fixture": W.hall()})
	for i: int in 3:
		s.add_bot("bot%d" % i, Vector2i(5 + i * 10, 10), "wander", 21 + i)
	s.place_stand_in(WorldIds.EntityKind.MOTH, Vector2i(20, 2))
	s.place_stand_in(WorldIds.EntityKind.TAPPER, Vector2i(20, 17))
	var moth: KitCreature = s.run.creatures.creature_of_kind(WorldIds.EntityKind.MOTH)
	var tapper: KitCreature = s.run.creatures.creature_of_kind(WorldIds.EntityKind.TAPPER)
	moth.max_speed = 5.0
	tapper.max_speed = 3.0
	moth.drift = Vector2(0.25, 0.0)
	tapper.drift = Vector2(-0.15, 0.0)
	s.on_tick = func(sc: Scenario) -> void:
		for c: KitCreature in [moth, tapper]:
			var x: float = c.position(sc.run).x
			if (x > 36.0 and c.drift.x > 0.0) or (x < 3.0 and c.drift.x < 0.0):
				c.drift = -c.drift
	s.step(2000)
	assert_eq(s.run.creatures.teleport_violations, 0, "2,000 ticks at full speed, never a jump")
	moth.drift = Vector2.ZERO
	s.run.registry.move(moth.entity_id, moth.position(s.run) + Vector2(3.0, 0.0))
	s.step(1)
	assert_eq(s.run.creatures.teleport_violations, 1, "a planted jump is caught")
	if OS.is_debug_build():
		assert_push_error("in one tick")
	assert_eq(s.run.creatures.log.of_type(&"teleport").size(), 1)
