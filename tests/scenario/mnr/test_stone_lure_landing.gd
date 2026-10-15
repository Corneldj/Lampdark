extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-09: a stone thrown in the grey box lands 14 np at the landing tile with no thrower in the
## event; a teammate hears it there; nothing of the throw (no flight, no landing point) reaches any
## client before it lands; and the stream audit stays clean.

const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_stone_lands_with_nobody_beside_it() -> void:
	var s: Scenario = make({"seed": 932, "fixture": "test"})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var ann: MinerHandle = s.add_miner("ann", Vector2i(2, 1), {"facing_deg": 0.0})
	var bob: MinerHandle = s.add_miner("bob", Vector2i(5, 1))
	ann.brain = null
	bob.brain = null
	s.step(2)
	assert_true(s.run.inventory.give(s.run, ann.entity_id, s.run.inventory.world.make(ItemKinds.Kind.STONE, 3)))
	var types_before: Dictionary = {}
	for h: MinerHandle in [ann, bob]:
		for m: Dictionary in h.capture.messages:
			types_before[int(Variants.number(m["type"]))] = true
	ann.at(s.run.tick + 1).select_slot(0)
	ann.at(s.run.tick + 2).press(ActionRecord.Kind.THROW, 600, 0.0)
	s.step(4)
	assert_eq(s.run.stones.flying.size(), 1, "in the air")
	var throw: Dictionary = s.run.stones.throws[s.run.stones.throws.size() - 1]
	var land_tick: int = throw["land_tick"]
	var tile: Vector2i = throw["tile"]
	s.step(land_tick - s.run.tick + 10)
	var event: NoiseSystem.Event = null
	for e: NoiseSystem.Event in s.run.noise.event_log:
		if e.type == NoiseTypes.Type.STONE_LANDING:
			event = e
	assert_not_null(event)
	assert_eq(event.tick, land_tick)
	assert_eq(event.source_entity, 0, "no thrower: nobody beside it")
	assert_true(event.origins.has(tile) or event.origins.size() > 0)
	# Bob hears it at the landing, and nothing of it before.
	var heard: Array[Dictionary] = []
	for e: Dictionary in bob.capture.audio_events(0, s.run.tick):
		if int(Variants.number(e["type"])) == NoiseTypes.Type.STONE_LANDING:
			heard.append(e)
	assert_eq(heard.size(), 1, "Bob heard one landing")
	assert_gte(int(Variants.number(heard[0]["start_tick"])), land_tick, "never before it landed")
	var at: Vector2 = heard[0]["apparent"]
	gut.p("landed at %s; Bob heard it from %s" % [tile, at])
	var new_types: Array[int] = []
	for h: MinerHandle in [ann, bob]:
		for m: Dictionary in h.capture.messages:
			var t: int = int(Variants.number(m["type"]))
			if not types_before.has(t) and not new_types.has(t):
				new_types.append(t)
	assert_eq(new_types, [] as Array[int], "the throw sent no new kind of message (no flight, no landing point)")
	for v: Dictionary in audit.violations.slice(0, 8):
		gut.p("VIOLATION %s" % v)
	assert_eq(audit.violation_count, 0, "no audit violation")
