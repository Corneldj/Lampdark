extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-01: the same seed and inputs give identical state hashes with creatures spawned, drawing
## from their streams, telling, winding up and moving.

const W = preload("res://tests/scenario/creatures/creature_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _build() -> Scenario:
	var s: Scenario = Scenario.create({"seed": 51, "fixture": W.hall()})
	s.add_bot("ann", s.fixture.spot("a"), "wander", 5)
	s.add_bot("bob", Vector2i(30, 10), "wander", 6)
	s.place_stand_in(WorldIds.EntityKind.MOTH, Vector2i(20, 2))
	s.place_stand_in(WorldIds.EntityKind.TAPPER, Vector2i(20, 17))
	var moth: KitCreature = s.run.creatures.creature_of_kind(WorldIds.EntityKind.MOTH)
	moth.drift = Vector2(0.1, 0.05)
	s.on_tick = func(sc: Scenario) -> void:
		var cs: CreatureSystem = sc.run.creatures
		if sc.run.tick % 40 == 5:
			cs.begin_tell(sc.run, moth, &"moth_rustle", 12.0)
		if sc.run.tick % 40 == 20:
			var tapper: Creature = cs.creature_of_kind(WorldIds.EntityKind.TAPPER)
			Tell.placed_points(sc.run, tapper.rng, tapper.position(sc.run))
			var ann: MinerHandle = sc.miners[0]
			cs.begin_wind_up(sc.run, tapper, ann.slot, ann.entity_id, 0.5, func(r: RunState) -> bool:
				return r.registry.get_entity(ann.entity_id).position.x < 20.0)
	return s


func test_twice() -> void:
	var result: Dictionary = Scenario.assert_deterministic(_build, 200)
	assert_true(Variants.flag(result["ok"]), "identical runs (first mismatch at tick %d)" % int(Variants.number(result["mismatch_tick"])))
	gut.p("creatures final state hash: %s" % str(result["final_hash"]))
