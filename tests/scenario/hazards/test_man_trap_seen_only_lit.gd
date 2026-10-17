extends "res://tests/scenario/kit/scenario_test.gd"
## HAZ-01 (Gameplay §8.2, §5.2; VIS-03, NET-08): the jaws reach a client only lit to 0.30 in its
## cone, as a small thing with its identity; under 0.30, or out of the cone, nothing about them, and
## never a fringe token. Sprung, the same record says so. NET-08's stream audit finds nothing sent
## that the miner could not perceive.

const T = preload("res://tests/unit/hazards/trap_world.gd")
const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


## The trap's record in a client's view at `level` (2: identity, 1: a token), or {}.
static func _record(h: MinerHandle, level: int) -> Dictionary:
	for raw: Variant in h.connection.view.entities.keys():
		var e: Dictionary = h.connection.view.entities[raw]
		if Variants.whole(e.get("level", 0)) != level:
			continue
		if level == 1 or Variants.whole(e.get("size_or_kind", 0)) == SeenKind.Kind.TRAP:
			return e
	return {}


func test_seen_only_lit_to_point_three_in_the_cone() -> void:
	var s: Scenario = make(T.cfg(4501))
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var trap: int = s.run.man_traps.place(s.run, T.TRAP)
	var ann: MinerHandle = T.miner_at(s, "ann", Vector2(T.TRAP) + Vector2(-5.5, 0.5))
	ann.at(s.run.tick).face(0.0)
	s.step(6)
	assert_true(_record(ann, 2).is_empty(), "in the dark the jaws are not seen")
	var lamp: GauzeLamp = T.L.lit_in_hand(s, ann, LampRules.WICK_UP)
	var centre: Vector2 = s.run.registry.get_entity(trap).position
	var tokens: int = 0
	var dim_steps: int = 0
	var seen_at: float = -1.0
	# She walks up to it: at every step under 0.30 nothing about it, from 0.30 its identity.
	for i: int in 9:
		s.run.movement.place(s.run, ann.entity_id, Vector2(T.TRAP) + Vector2(-5.5 + 0.5 * i, 0.5))
		s.step(6)
		var light: float = float(s.run.light.grid.value_at(centre)) / 1000.0
		var seen: Dictionary = _record(ann, 2)
		tokens += 0 if _record(ann, 1).is_empty() else 1
		if light < 0.30:
			dim_steps += 1
			assert_true(seen.is_empty(), "at %.2f nothing about the jaws" % light)
		else:
			assert_false(seen.is_empty(), "at %.2f in her cone, the jaws are seen" % light)
			if seen_at < 0.0:
				seen_at = light
				var at: Vector2 = seen.get("position", Vector2.ZERO)
				assert_lt(at.distance_to(centre), 0.5, "where they lie")
				assert_eq(Variants.whole(seen.get("in_hand", 0)) & SeenKind.TRAP_SPRUNG, 0, "set")
	assert_gt(dim_steps, 0, "some steps under 0.30 (%d)" % dim_steps)
	assert_gte(seen_at, 0.30, "seen once lit to 0.30 (first at %.2f)" % seen_at)
	assert_eq(tokens, 0, "never a fringe token")
	ann.at(s.run.tick).face(180.0)
	s.step(6)
	assert_true(_record(ann, 2).is_empty(), "out of her cone, not seen")
	ann.at(s.run.tick).face(0.0)
	s.step(6)
	s.run.stones.landed.emit(T.TRAP)
	s.step(6)
	var sprung: Dictionary = _record(ann, 2)
	assert_false(sprung.is_empty())
	assert_ne(Variants.whole(sprung.get("in_hand", 0)) & SeenKind.TRAP_SPRUNG, 0, "sprung, the record says so")
	assert_true(lamp.burning())
	for v: Dictionary in audit.violations.slice(0, 8):
		gut.p(str(v))
	assert_eq(audit.violation_count, 0, "NET-08: nothing sent she could not perceive")
