extends "res://tests/scenario/kit/scenario_test.gd"
## The first playtest's fixes, end to end: a thing lying lit to identity reaches the client with its
## kind, so the glyph names it ("Pick up a spanner"); a solo miner pinned is told so (STATUS: the
## body's cues and the self-rescue offer), a failed attempt is reported, a successful one frees them;
## NET-08's audit judges every STATUS record and finds it the receiving miner's own.

const B = preload("res://tests/unit/mnr/belt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")
const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _solo(run_seed: int, overrides: Dictionary = {}) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": B.room(), "overrides": overrides})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"), {"facing_deg": 0.0})
	ann.brain = null
	ann.at(0).face(0.0)
	L.lit_in_hand(s, ann)
	s.step(3)
	return [s, ann, audit]


func test_a_lying_thing_reaches_the_client_named() -> void:
	var w: Array = _solo(181)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var at: Vector2i = s.fixture.spot("a") + Vector2i(1, 0)
	B.put(s, ItemKinds.Kind.SPANNER, at)
	s.step(6)
	var seen: Dictionary = {}
	for raw: Variant in ann.connection.view.entities.keys():
		var e: Dictionary = ann.connection.view.entities[raw]
		if int(Variants.number(e.get("size_or_kind", 0))) == SeenKind.Kind.ITEM:
			seen = e
	assert_false(seen.is_empty(), "the spanner, identified")
	assert_eq(int(Variants.number(seen.get("in_hand", 0))) & 0x3F, ItemKinds.Kind.SPANNER, "its kind rides on its record")
	var glyph: Dictionary = InteractionGlyph.pick(ann.connection.view, Tuning.f(&"vision.touch_range_tiles"))
	assert_eq(str(glyph.get("verb_key", "")), "verb.pick_up")
	assert_eq(str(glyph.get("object_key", "")), "item.spanner", "the glyph names it")
	var audit: StreamAudit = w[2]
	assert_eq(audit.violation_count, 0)


func test_a_solo_pin_is_explained_and_a_failed_struggle_reported() -> void:
	var w: Array = _solo(182, {"rescue.self_rescue_chance": 0.0})
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	assert_true(AloneRules.is_alone(s.run, ann.entity_id), "a friends lobby of one plays the solo rules")
	var id: int = s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.TAPPER_PIN, 0, 600)
	assert_ne(id, -1)
	s.step(3)
	var st: Dictionary = ann.connection.status
	assert_ne(int(Variants.number(st.get("cues", 0))) & MinerCues.HALF_IN_WALL, 0, "the client knows it is pinned")
	assert_ne(int(Variants.number(st.get("flags", 0))) & StatusWire.SELF_RESCUE_OFFERED, 0, "and that it may struggle")
	var ticks: int = roundi(Tuning.f(&"rescue.self_rescue_hold_s") * Tuning.f(&"net.tick_hz")) + 4
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, ticks)
	s.step(ticks + 3)
	st = ann.connection.status
	assert_eq(s.run.miner_state.life(ann.entity_id), MinerTransitions.Life.GRABBED, "still pinned (the roll failed)")
	assert_ne(int(Variants.number(st.get("flags", 0))) & StatusWire.SELF_RESCUE_FAILED, 0, "the failure is reported")
	assert_eq(int(Variants.number(st.get("flags", 0))) & StatusWire.SELF_RESCUE_OFFERED, 0, "and no second attempt offered")
	var audit: StreamAudit = w[2]
	var checked: Dictionary = audit.report()["checked"]
	assert_gt(int(Variants.number(checked.get("status", 0))), 0, "STATUS records were judged")
	assert_eq(audit.violation_count, 0, "each the receiving miner's own")


func test_a_successful_struggle_frees_the_miner() -> void:
	var w: Array = _solo(183, {"rescue.self_rescue_chance": 1.0})
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.TAPPER_PIN, 0, 600)
	s.step(3)
	var ticks: int = roundi(Tuning.f(&"rescue.self_rescue_hold_s") * Tuning.f(&"net.tick_hz")) + 4
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, ticks)
	s.step(ticks + 3)
	assert_eq(s.run.miner_state.life(ann.entity_id), MinerTransitions.Life.UPRIGHT, "free")
	assert_eq(int(Variants.number(ann.connection.status.get("cues", 0))) & MinerCues.HALF_IN_WALL, 0, "the client's status follows")
