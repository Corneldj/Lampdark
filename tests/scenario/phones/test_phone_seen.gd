extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-12 (Gameplay §6.6, §5.2): what a client learns of a phone is what its miner sees. In the dark,
## nothing (no position, never a token: a phone is a small thing); lit to 0.30 in the cone, a phone
## with its painted number on its identity record, and what anyone beside it can tell: its glyph
## reads Crank, Hang up while someone is on it, Answer while it rings. Its road home and its cut are
## never sent: NET-08's stream audit finds nothing beyond what the miner perceives.

const P = preload("res://tests/unit/phones/phone_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")
const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


static func _phone_seen(h: MinerHandle) -> Dictionary:
	for raw: Variant in h.connection.view.entities.keys():
		var e: Dictionary = h.connection.view.entities[raw]
		if int(Variants.number(e.get("size_or_kind", 0))) == SeenKind.Kind.PHONE and int(Variants.number(e.get("level", 0))) == 2:
			return e
	return {}


static func _verb(h: MinerHandle) -> String:
	var e: Dictionary = _phone_seen(h)
	return InteractionVerbs.for_seen(SeenKind.Kind.PHONE, 0, int(Variants.number(e.get("in_hand", 0))))


static func _any_phone(h: MinerHandle) -> bool:
	for raw: Variant in h.connection.view.entities.keys():
		var e: Dictionary = h.connection.view.entities[raw]
		if int(Variants.number(e.get("size_or_kind", 0))) == SeenKind.Kind.PHONE:
			return true
	return false


func test_seen_only_lit_with_its_number() -> void:
	var s: Scenario = make({"seed": 5001, "fixture": P.road()})
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	P.power(s)
	var p: PitPhone = P.phone(s, "p1", Vector2i(8, 2), [[Vector2i.ZERO, 1]])
	var ann: MinerHandle = P.miner(s, "ann", Vector2i(6, 2))
	ann.at(s.run.tick).face(0.0)
	s.step(6)
	assert_false(_any_phone(ann), "in the dark: nothing of the phone, not even a token")
	L.lit_in_hand(s, ann)
	s.step(6)
	var seen: Dictionary = _phone_seen(ann)
	assert_false(seen.is_empty(), "lit, the phone is seen")
	assert_eq(int(Variants.number(seen.get("in_hand", 0))), p.number, "with its painted number")
	assert_eq(_verb(ann), "verb.crank", "its glyph: Crank")
	var at: Vector2 = seen.get("position", Vector2.ZERO)
	assert_lt(at.distance_to(Vector2(8.5, 2.5)), 0.5, "where it hangs")
	# A call and a cut: nothing new reaches her but the crank she makes, and that she is on it.
	s.run.movement.place(s.run, ann.entity_id, Vector2(7.5, 2.5))
	s.step(2)
	P.press(s, ann, 50)
	s.step(2)
	assert_eq(p.caller, ann.entity_id)
	assert_eq(_verb(ann), "verb.hang_up", "on it: Hang up")
	s.run.phones.on_tiles_fallen(s.run, Vector2i.ZERO, [] as Array[Vector2i], 1)
	assert_true(p.cut)
	s.step(10)
	assert_eq(int(Variants.number(_phone_seen(ann).get("in_hand", 0))), p.number, "cut, the phone looks as it did")
	assert_eq(_verb(ann), "verb.crank")
	var other: PitPhone = P.phone(s, "p2", Vector2i(9, 3))
	assert_true(s.run.phones.ring(s.run, other.number, 0))
	s.step(4)
	var rung: bool = false
	for raw: Variant in ann.connection.view.entities.keys():
		var e: Dictionary = ann.connection.view.entities[raw]
		if int(Variants.number(e.get("size_or_kind", 0))) == SeenKind.Kind.PHONE and (int(Variants.number(e.get("in_hand", 0))) & SeenKind.PHONE_NUMBER_MASK) == other.number:
			rung = InteractionVerbs.for_seen(SeenKind.Kind.PHONE, 0, int(Variants.number(e.get("in_hand", 0)))) == "verb.answer"
	assert_true(rung, "a ringing phone: Answer")
	s.step(60)
	assert_eq(other.ringing_until, -1, "the burst over")
	for v: Dictionary in audit.violations.slice(0, 8):
		gut.p("VIOLATION %s" % v)
	assert_eq(audit.violation_count, 0, "nothing sent beyond what she perceives")
