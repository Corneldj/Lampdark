extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-01: exactly one creature of each enabled kind; a second spawn fails; Quiet Seam creates no
## Tapper; a start tile in any client's seen set or margin waits, and the creature appears only
## once the tile is clear.

const W = preload("res://tests/scenario/creatures/creature_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_one_of_each_enabled_kind() -> void:
	var s: Scenario = make({"seed": 1, "fixture": W.hall()})
	s.add_miner("ann", s.fixture.spot("a"))
	assert_ne(s.place_creature(WorldIds.EntityKind.MOTH, Vector2i(30, 2)), 0)
	assert_ne(s.place_creature(WorldIds.EntityKind.TAPPER, Vector2i(30, 16)), 0)
	assert_eq(s.place_creature(WorldIds.EntityKind.MOTH, Vector2i(32, 2)), 0, "a second Moth")
	assert_push_error("one of each per run")
	assert_eq(s.place_creature(WorldIds.EntityKind.TAPPER, Vector2i(32, 16)), 0, "a second Tapper")
	assert_push_error("one of each per run")
	assert_eq(s.place_creature(WorldIds.EntityKind.STYTHE, Vector2i(34, 8)), 0, "the Stythe is off in M1")
	assert_eq(s.run.creatures.log.of_type(&"spawn_refused").size(), 1)
	s.step(5)
	assert_eq(s.run.creatures.creatures.size(), 2)
	var kinds: Array[int] = []
	for id: int in s.run.registry.ids():
		var k: int = s.run.registry.get_entity(id).kind
		if CreatureSystem.DOMAINS.has(k):
			kinds.append(k)
	kinds.sort()
	assert_eq(kinds, [WorldIds.EntityKind.MOTH, WorldIds.EntityKind.TAPPER] as Array[int], "exactly one of each in the world")


func test_stythe_when_enabled() -> void:
	Tuning.set_dev_override("creatures.enabled", {"moth": 1, "tapper": 1, "stythe": 1})
	var s: Scenario = make({"seed": 2, "fixture": W.hall()})
	assert_ne(s.place_creature(WorldIds.EntityKind.STYTHE, Vector2i(34, 8)), 0)
	assert_eq(s.place_creature(WorldIds.EntityKind.STYTHE, Vector2i(35, 8)), 0)
	assert_push_error("one of each per run")
	Tuning.clear_dev_overrides()


func test_quiet_seam_has_no_tapper() -> void:
	var s: Scenario = make({"seed": 3, "fixture": W.hall()})
	s.run.creatures.conditions = ["quiet_seam"] as Array[String]
	assert_eq(s.place_creature(WorldIds.EntityKind.TAPPER, Vector2i(30, 16)), 0)
	assert_ne(s.place_creature(WorldIds.EntityKind.MOTH, Vector2i(30, 2)), 0)
	var refused: Dictionary = s.run.creatures.log.of_type(&"spawn_refused")[0]
	assert_eq(str(refused["reason"]), "quiet seam")


func test_never_on_a_seen_or_margin_tile() -> void:
	var s: Scenario = make({"seed": 4, "fixture": W.hall()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"), {"facing_deg": 0.0})
	ann.at(0).face(0.0)
	var lamp: int = s.run.light.grid.add_point("gauze_lamp", 1, ann.entity_id, 0, 4.0, 1.0, Vector2(5.5, 10.5), 0)
	s.step(3)
	var seen: Vector2i = Vector2i(7, 10)
	var margin: Vector2i = Vector2i(11, 10)
	assert_true(s.run.vision.native.is_seen_or_margin_of_any(seen))
	assert_eq(s.run.vision.native.margin_band(ann.slot, margin), 1, "a geometry-margin tile")
	var moth: Creature = KitCreature.new(WorldIds.EntityKind.MOTH)
	assert_eq(s.run.creatures.spawn(s.run, moth, seen), ERR_BUSY, "a seen start tile: the spawn waits")
	assert_push_error("seen or in a margin")
	var tapper: Creature = KitCreature.new(WorldIds.EntityKind.TAPPER)
	assert_eq(s.run.creatures.spawn(s.run, tapper, margin), ERR_BUSY, "a margin tile too")
	assert_push_error("seen or in a margin")
	s.step(10)
	assert_eq(moth.entity_id, 0, "still waiting while Ann's lamp shows the tile")
	assert_eq(tapper.entity_id, 0)
	assert_eq(s.place_creature(WorldIds.EntityKind.MOTH, Vector2i(30, 2)), 0, "a waiting Moth is still the run's one Moth")
	assert_push_error("one of each per run")
	s.run.light.grid.remove_source(lamp)
	s.step(3)
	assert_ne(moth.entity_id, 0, "dark again: it appears")
	assert_ne(tapper.entity_id, 0)
	for c: Creature in s.run.creatures.creatures:
		assert_false(s.run.vision.native.is_seen_or_margin_of_any(c.tile(s.run)), "never placed while watched")
