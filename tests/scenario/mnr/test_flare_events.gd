extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-09: a flare struck in the grey box, under NET-08's audit: one 16 np strike event, a VIS-02
## "flare" source that appears (CRT-03's wake check hears it) and lasts exactly 8 s, a naked flame
## for HAZ-04 on every tile it enters, and every Moth holding it as a beacon while it burns. Stub
## consumers record what they were given; nothing in any stream breaks the audit.

const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_flare_struck_in_the_grey_box() -> void:
	var s: Scenario = make({"seed": 931, "fixture": "test"})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var ann: MinerHandle = s.add_miner("ann", Vector2i(2, 1), {"facing_deg": 0.0})
	var bob: MinerHandle = s.add_miner("bob", Vector2i(5, 1))
	ann.brain = null
	bob.brain = null
	var moth: int = s.place_creature(WorldIds.EntityKind.MOTH, Vector2i(12, 2))
	s.step(2)
	assert_true(s.run.inventory.give(s.run, ann.entity_id, s.run.inventory.world.make(ItemKinds.Kind.FLARE, 1)))
	var added: Array[String] = []
	s.run.light.grid.source_added.connect(func(_id: int, kind: String, _pos: Vector2) -> void: added.append(kind))
	var flames: Array[Vector2i] = []
	s.run.lamps.naked_flame.connect(func(tile: Vector2i, cause: String) -> void:
		if cause == "burning_flare":
			flames.append(tile))
	var events_before: int = s.run.noise.event_log.size()
	ann.at(s.run.tick + 1).select_slot(0)
	ann.at(s.run.tick + 2).hold(InputRecord.HOLD_USE, 14)
	s.step(16)
	var flare: Item = s.run.inventory.hands_of(ann.entity_id).free_hand
	assert_true(HandsAndBelt.burning_flare(flare), "struck")
	var source: int = s.run.flares.source_of(flare)
	assert_true(added.has("flare"), "the source appeared (CRT-03's wake check)")
	var strikes: int = 0
	for e: NoiseSystem.Event in s.run.noise.event_log.slice(events_before):
		if e.type == NoiseTypes.Type.FLARE_STRIKE:
			strikes += 1
			assert_almost_eq(e.level_np, 16.0, 1e-6)
	assert_eq(strikes, 1, "one 16 np strike")
	var c: Moth = s.run.creatures.creature_of(moth) as Moth
	assert_true(c.awake.perception.beacons.has(source), "the Moth has it as a beacon")
	var b: Dictionary = c.awake.perception.beacons[source]
	var kind: StringName = b["kind"]
	assert_eq(kind, &"flare")
	ann.at(s.run.tick + 1).move(0.0, InputRecord.Gait.WALK, 40)
	s.step(160)
	assert_false(s.run.light.grid.has_source(source), "gone after 8 s")
	assert_gte(flames.size(), 3, "a naked flame on striking and on every tile it entered")
	gut.p("naked flames: %s" % [flames])
	for v: Dictionary in audit.violations.slice(0, 8):
		gut.p("VIOLATION %s" % v)
	assert_eq(audit.violation_count, 0, "no audit violation")
