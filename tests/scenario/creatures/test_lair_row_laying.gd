extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-15, under NET-08's audit: a drag reaching the lair lays the body straight in the next slot
## of the row, kept in the lair, and the Stythe enters Keep; a body it collects next goes in the
## following slot, its trail converging on the lair. Home before the victim's 20 s are out, it
## holds them in the lair until they fall, then lays them. The arrival is logged with the drag's
## length; nothing of the lair, the kept bodies or lair time reaches a client.

const H = preload("res://tests/scenario/creatures/stythe_hunt_world.gd")
const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_drag_home_lays_the_body_in_the_row() -> void:
	var s: Scenario = make({"seed": 1501, "fixture": H.road(), "overrides": H.W.ON})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var h: H = H.new()
	h.build(s, 40, 37, 95)
	var lair: StytheLair = h.st.home
	assert_not_null(lair, "its lair attached at spawn")
	var row: Array[Vector2i] = lair.row()
	assert_eq(row[0], Vector2i(91, 2), "the stand-in row: the lair's floor in row-major order")
	assert_true(h.until_state(&"drag", 300))
	var grab_tile: Vector2i = h.st.drag.tiles[0]["tile"]
	assert_true(h.until_state(&"keep", 1600), "home, it keeps")
	var ann: int = h.ann.entity_id
	assert_eq(s.run.registry.get_entity(ann).tile(), row[0], "laid in the first slot")
	assert_eq(s.run.miner_state.life(ann), MinerTransitions.Life.UNCONSCIOUS, "unconscious: the 20 s ran out on the way")
	assert_true(s.run.falls.body_of(ann).kept_in_lair, "kept in the lair")
	assert_eq(h.st.kept, [ann] as Array[int])
	assert_null(s.run.holds.grab_of(ann), "no longer grabbed")
	assert_eq(lair.arrivals.size(), 1)
	var dragged: int = int(Variants.number(lair.arrivals[0]["dragged_tiles"]))
	assert_gte(dragged, 50, "the drag's length logged for the Inquiry (%d tiles)" % dragged)
	for x: int in range(grab_tile.x, row[0].x + 1):
		assert_eq(lair.trail.direction_at(Vector2i(x, 2)), 0, "every tile from the grab to the lair points east, at %d" % x)
		assert_eq(int(Variants.number(s.run.vision.trails.get(Vector2i(x, 2), -1))), 0, "and is VIS-10's trail")
	assert_eq(lair.trail.direction_at(grab_tile - Vector2i(1, 0)), -1, "never behind the grab: it never leads home")
	s.step(20)
	assert_eq(h.st.state.name, &"keep", "keeping while she lies there")
	for v: Dictionary in audit.violations.slice(0, 8):
		gut.p(str(v))
	assert_eq(audit.violation_count, 0, "nothing of the lair, the kept or lair time in any stream")


func test_a_collected_body_goes_in_the_next_slot() -> void:
	var s: Scenario = make({"seed": 1502, "fixture": H.road(), "overrides": H.W.ON})
	var h: H = H.new()
	h.build(s, 40, 37, 95)
	assert_true(h.until_state(&"keep", 1900))
	var lair: StytheLair = h.st.home
	var bob: MinerHandle = H.W.miner(s, "bob", Vector2i(80, 2), 0.0)
	assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.MOTH_SMOTHER))
	assert_true(s.run_until(func(_sv: Variant) -> bool: return lair.arrivals.size() >= 2, 4000), "after its check, it collects him and comes home")
	s.step(2)
	assert_eq(s.run.registry.get_entity(bob.entity_id).tile(), lair.row()[1], "the next slot")
	assert_eq(h.st.kept.size(), 2)
	assert_eq(lair.trail.direction_at(Vector2i(85, 2)), 0, "his trail runs to the lair too: they converge")


func test_home_before_the_twenty_seconds_it_holds_them() -> void:
	var s: Scenario = make({"seed": 1503, "fixture": H.road(), "overrides": H.W.ON})
	var h: H = H.new()
	h.build(s, 40, 37, 52)
	assert_true(h.until_state(&"drag", 300))
	var grabbed: int = s.run.holds.grab_of(h.ann.entity_id).began_tick
	s.step(150)
	assert_true(h.st.home.is_lair(h.st.tile(s.run)), "home within 150 ticks")
	assert_eq(h.st.state.name, &"drag", "still holding her: her 20 s are not out")
	assert_eq(s.run.miner_state.life(h.ann.entity_id), MinerTransitions.Life.GRABBED)
	assert_true(h.until_state(&"keep", 400))
	assert_gte(s.run.tick - grabbed, 400, "laid once she fell")
	assert_eq(s.run.registry.get_entity(h.ann.entity_id).tile(), h.st.home.row()[0])
