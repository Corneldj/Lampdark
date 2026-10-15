extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-14, under NET-08's audit: the Stythe hunts Ann, snuffs her lamp, winds up for 12 ticks within
## 1.5 tiles (the intake of breath plays) and grabs her: her lamp dropped snuffed at the grab tile,
## her belt with her, Grabbed, exactly one grab. It drags her east at 2.0 tiles/s, a 9 np scrape every
## 20 ticks, her voice on the dragged route; at 400 ticks she falls unconscious with a muffled scream
## and it drags on. Nothing of its state or her route reaches any client.

const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")
const H = preload("res://tests/scenario/creatures/stythe_hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_hunt_windup_grab_and_drag() -> void:
	var s: Scenario = make({"seed": 1401, "fixture": H.road(), "overrides": H.W.ON})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var h: H = H.new()
	h.build(s)
	var ann: MinerHandle = h.ann
	var st: StytheCreature = h.st
	# Her lamp, shuttered (a flame it must snuff first); a kit on her belt.
	H.W.miner(s, "far", Vector2i(2, 2))
	var lamp: GauzeLamp = s.run.lamps.create(s.run, 1.0, 0, true, LampRules.WICK_NORMAL, Vector2(37.5, 2.5))
	s.step(1)
	s.run.lamps.pick_up(s.run, lamp, ann.entity_id)
	s.run.lamps.shutter(s.run, lamp, false)
	assert_true(s.run.inventory.give(s.run, ann.entity_id, s.run.inventory.world.make(ItemKinds.Kind.HEALING_KIT)))
	var grabs: Array[int] = []
	s.run.holds.grab_begun.connect(func(_id: int, _k: GrabHold.Kind, _c: int, victim: int) -> void: grabs.append(victim))
	var events_before: int = s.run.noise.event_log.size()
	assert_true(h.until_state(&"hunt", 60), "it hunts her")
	assert_true(h.until_state(&"windup", 200), "a wind-up")
	var w: CreatureWindUp = st.wind_up
	assert_eq(w.end_tick - w.start_tick, 12, "0.6 s: 12 ticks")
	assert_false(lamp.burning(), "only once her flame is out")
	assert_lte(s.run.registry.get_entity(ann.entity_id).position.distance_to(st.position(s.run)), 1.5 + 1e-6, "within 1.5 tiles")
	var intake: bool = false
	for d: Dictionary in s.run.audio.deliveries:
		intake = intake or int(Variants.number(d["tick"])) == w.start_tick and int(Variants.number(d["client"])) == ann.slot
	assert_true(intake, "the intake of breath reached her")
	var grab_tile: Vector2i = s.run.registry.get_entity(ann.entity_id).tile()
	assert_true(h.until_state(&"drag", 30), "the grab lands")
	assert_eq(grabs, [ann.entity_id] as Array[int], "exactly one grab")
	assert_eq(s.run.miner_state.life(ann.entity_id), MinerTransitions.Life.GRABBED)
	var lying: GauzeLamp = lamp
	assert_false(lying.held(), "her lamp out of her hand")
	assert_eq(Vector2i(lying.at), grab_tile, "dropped at the grab tile")
	assert_false(lying.burning(), "snuffed")
	assert_eq(s.run.inventory.hands_of(ann.entity_id).count_of(ItemKinds.Kind.HEALING_KIT), 1, "her belt goes with her")
	assert_eq(int(Variants.number(s.run.voice.route_of.get(ann.slot, -1))), VoiceRoutes.Route.DRAGGED, "her voice at whisper range")
	var start: Vector2 = st.position(s.run)
	var grabbed_at: int = s.run.holds.grab_of(ann.entity_id).began_tick
	s.step(100)
	var speed: float = st.position(s.run).distance_to(start) / 5.0
	gut.p("dragged %.2f tiles/s" % speed)
	assert_almost_eq(speed, 2.0, 0.1, "2.0 tiles/s")
	assert_eq(s.run.registry.get_entity(ann.entity_id).position, st.position(s.run), "she rides on it")
	var scrapes: Array[NoiseSystem.Event] = []
	for e: NoiseSystem.Event in s.run.noise.event_log.slice(events_before):
		if e.type == NoiseTypes.Type.DRAG_SCRAPE:
			scrapes.append(e)
	assert_gte(scrapes.size(), 5)
	for i: int in range(1, scrapes.size()):
		assert_eq(scrapes[i].tick - scrapes[i - 1].tick, 20, "a scrape every 20 ticks")
		assert_almost_eq(scrapes[i].level_np, 9.0, 1e-6, "9 np")
	var fell: Array[Dictionary] = []
	s.run.falls.fell.connect(func(r: Dictionary) -> void: fell.append(r))
	s.run_until(func(_sv: Variant) -> bool: return not fell.is_empty(), 400)
	assert_eq(fell.size(), 1, "she falls unconscious")
	# RSC-03 counts the grab's own tick: held through ticks g .. g + 399, 400 in all.
	assert_eq(int(Variants.number(fell[0]["tick"])) - grabbed_at + 1, 400, "after 400 ticks held")
	assert_eq(int(Variants.number(fell[0]["cause"])), FallCause.Cause.DRAG)
	var at: Vector2 = st.position(s.run)
	s.step(40)
	assert_gt(st.position(s.run).distance_to(at), 1.0, "the drag goes on")
	assert_eq(st.state.name, &"drag")
	for v: Dictionary in audit.violations.slice(0, 8):
		gut.p("VIOLATION %s" % v)
	assert_eq(audit.violation_count, 0, "nothing of its state or her route in any stream")
