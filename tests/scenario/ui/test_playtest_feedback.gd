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


## A player struggling as a person would: watching the needle on their own screen, pressing once
## per zone when it is well inside (the press is judged at the tick that screen showed).
static func _struggle(s: Scenario, ann: MinerHandle, limit: int) -> int:
	var pressed_zone: float = -1.0
	for i: int in limit:
		var st: Dictionary = ann.connection.status
		if (int(Variants.number(st.get("flags", 0))) & StatusWire.STRUGGLE) != 0:
			var stamp: PackedInt64Array = ann.connection.shown_stamp(Transport.now_usec())
			var shown: float = float(stamp[0])
			var size: float = Variants.number(st["zone_size"])
			var zone: float = Variants.number(st["zone_start"])
			var d: float = fposmod(StatusWire.needle_deg(st, shown) - zone, 360.0)
			var lockout: float = Variants.number(st["lockout_until"])
			if d > size * 0.3 and d < size * 0.7 and shown >= lockout and zone != pressed_zone:
				ann.at(s.run.tick).press(ActionRecord.Kind.STRUGGLE)
				pressed_zone = zone
		s.step(1)
		if s.run.miner_state.life(ann.entity_id) != MinerTransitions.Life.GRABBED:
			return i
	return -1


func test_a_pin_is_explained_and_struggled_free_over_a_lagged_link() -> void:
	var w: Array = _solo(182)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	ann.link(120, 0.0)
	var id: int = s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.TAPPER_PIN, 0, 600)
	assert_ne(id, -1)
	s.step(6)
	var st: Dictionary = ann.connection.status
	assert_ne(int(Variants.number(st.get("cues", 0))) & MinerCues.HALF_IN_WALL, 0, "the client knows it is pinned")
	assert_ne(int(Variants.number(st.get("flags", 0))) & StatusWire.STRUGGLE, 0, "and that it may struggle")
	assert_eq(int(Variants.number(st.get("needed", 0))), Tuning.i(&"rescue.struggle_hits"))
	var took: int = _struggle(s, ann, 400)
	gut.p("struggled free in %d ticks over a 120 ms link" % took)
	assert_ne(took, -1, "a player who presses in the zone breaks free")
	assert_eq(s.run.miner_state.life(ann.entity_id), MinerTransitions.Life.UPRIGHT)
	var hits: int = s.run.holds.events.filter(func(e: Dictionary) -> bool: return e["type"] == &"struggle_hit").size()
	var misses: int = s.run.holds.events.filter(func(e: Dictionary) -> bool: return e["type"] == &"struggle_miss").size()
	assert_eq(hits, Tuning.i(&"rescue.struggle_hits"), "three hits, the third freeing her")
	assert_eq(misses, 0, "never a miss for a press made inside the zone on her screen")
	var audit: StreamAudit = w[2]
	var checked: Dictionary = audit.report()["checked"]
	assert_gt(int(Variants.number(checked.get("status", 0))), 0, "STATUS records were judged")
	assert_eq(audit.violation_count, 0, "each the receiving miner's own")


func test_a_mashed_press_misses_and_shrinks_the_zone() -> void:
	var w: Array = _solo(183)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.TAPPER_PIN, 0, 600)
	s.step(4)
	var size: float = Variants.number(ann.connection.status.get("zone_size", 0.0))
	# A press the moment the needle is far from the zone.
	for _i: int in 40:
		var st: Dictionary = ann.connection.status
		var stamp: PackedInt64Array = ann.connection.shown_stamp(Transport.now_usec())
		var d: float = fposmod(StatusWire.needle_deg(st, float(stamp[0])) - float(Variants.number(st["zone_start"])), 360.0)
		if d > float(Variants.number(st["zone_size"])) + 60.0 and d < 300.0:
			ann.at(s.run.tick).press(ActionRecord.Kind.STRUGGLE)
			break
		s.step(1)
	s.step(8)
	var after: float = Variants.number(ann.connection.status.get("zone_size", 0.0))
	assert_almost_eq(after, size - Tuning.f(&"rescue.struggle_zone_shrink_deg"), 0.01, "missed: the zone shrank")
	assert_eq(s.run.miner_state.life(ann.entity_id), MinerTransitions.Life.GRABBED, "still pinned")
