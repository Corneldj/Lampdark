extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-12 (§4.6): no tool is a weapon. No action kind swings or strikes; no Use handler is registered
## for a tool; Use or interact with each tool selected, facing a Moth in touch range, starts nothing,
## sounds nothing and leaves the creature as it was.

const B = preload("res://tests/unit/mnr/belt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_no_action_kind_is_an_attack() -> void:
	for raw: Variant in ActionRecord.Kind.keys():
		var name: String = str(raw).to_lower()
		for word: String in ["attack", "hit", "swing", "strike", "melee"]:
			assert_false(name.contains(word), "%s is no attack" % name)


func test_a_tool_does_nothing_to_a_creature() -> void:
	var s: Scenario = make({"seed": 971, "fixture": B.room()})
	# Placed before anyone is there to see the tile (a creature never appears in sight, CRT-01).
	var moth: int = s.place_creature(WorldIds.EntityKind.MOTH, s.fixture.spot("a") + Vector2i(1, 0))
	s.step(1)
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"), {"facing_deg": 0.0})
	ann.brain = null
	s.step(2)  # in the dark: the Moth sleeps on, so anything it does is the tools' doing
	for kind: ItemKinds.Kind in ToolsParts.TOOLS:
		assert_false(s.run.inventory.use_handlers.has(kind), "no Use handler for %s" % ItemKinds.text_key(kind))
		assert_true(s.run.inventory.give(s.run, ann.entity_id, s.run.inventory.world.make(kind)))
	var c: Moth = s.run.creatures.creature_of(moth) as Moth
	assert_true(c.is_sleeping(), "asleep")
	var where: Vector2 = s.run.registry.get_entity(moth).position
	var log_before: int = s.run.creatures.log.entries.size()
	var events_before: int = s.run.noise.event_log.size()
	for slot: int in 4:
		ann.at(s.run.tick + 1).select_slot(slot)
		ann.at(s.run.tick + 2).hold(InputRecord.HOLD_USE, 30)
		s.step(35)
		assert_false(s.run.inventory.actions.has(ann.entity_id), "Use on slot %d starts nothing" % slot)
		ann.at(s.run.tick + 1).hold(InputRecord.HOLD_INTERACT, 30)
		s.step(35)
	for e: NoiseSystem.Event in s.run.noise.event_log.slice(events_before):
		assert_ne(e.source_entity, ann.entity_id, "no sound of hers")
	assert_eq(s.run.registry.get_entity(moth).position, where, "the Moth unmoved")
	assert_true(c.is_sleeping(), "and still asleep")
	assert_eq(s.run.creatures.log.entries.size(), log_before, "nothing in the creature log")
	for kind: ItemKinds.Kind in ToolsParts.TOOLS:
		assert_eq(s.run.inventory.hands_of(ann.entity_id).count_of(kind), 1)
