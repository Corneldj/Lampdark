extends "res://tests/scenario/kit/scenario_test.gd"
## HAZ-03 (Gameplay §12.5, §5.2; GDD §15.8): the tell, bowed props and dribbling stone, reaches a
## client only for an armed, standing point lit to 0.30 in its cone, as a small thing (never a
## token). Shuttered, it is gone; creaking, it is the same record (nothing says it creaks); fallen,
## it is gone for good. NET-08's stream audit finds nothing sent that the miner could not perceive.

const W = preload("res://tests/unit/hazards/collapse_world.gd")
const StreamAudit = preload("res://tools/stream_audit/stream_audit.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


static func _tell(h: MinerHandle) -> Dictionary:
	for raw: Variant in h.connection.view.entities.keys():
		var e: Dictionary = h.connection.view.entities[raw]
		if int(Variants.number(e.get("size_or_kind", 0))) == SeenKind.Kind.COLLAPSE_POINT and int(Variants.number(e.get("level", 0))) == 2:
			return e
	return {}


func test_seen_only_lit_and_standing() -> void:
	var s: Scenario = make(W.cfg(3901))
	var audit: StreamAudit = StreamAudit.new()
	audit.attach(s.run, s.net)
	var p: CollapsePoints.Point = W.arm(s)
	var ann: MinerHandle = W.miner_at(s, "ann", Vector2(12.5, 2.5))
	ann.at(s.run.tick).face(0.0)
	s.step(6)
	assert_true(_tell(ann).is_empty(), "in the dark the tell is not seen")
	var lamp: GauzeLamp = W.L.lit_in_hand(s, ann, LampRules.WICK_UP)
	s.step(6)
	var centre: Vector2 = s.run.registry.get_entity(p.tell).position
	assert_lt(float(s.run.light.grid.value_at(centre)) / 1000.0, 0.30, "4 tiles off, her pool is under 0.30 there")
	assert_true(_tell(ann).is_empty(), "so the tell is not seen")
	s.run.movement.place(s.run, ann.entity_id, Vector2(13.5, 2.5))
	s.step(6)
	assert_gte(float(s.run.light.grid.value_at(centre)) / 1000.0, 0.30, "a tile nearer, lit to 0.30 there")
	var seen: Dictionary = _tell(ann)
	assert_false(seen.is_empty(), "lit to 0.30 in her cone, the tell is seen")
	var at: Vector2 = seen.get("position", Vector2.ZERO)
	assert_lt(at.distance_to(centre), 0.5, "on the road where the props bow")
	ann.at(s.run.tick).face(180.0)
	s.step(6)
	assert_true(_tell(ann).is_empty(), "out of her cone, not seen")
	ann.at(s.run.tick).face(0.0)
	s.step(6)
	assert_false(_tell(ann).is_empty())
	var before: Dictionary = _tell(ann).duplicate()
	W.trigger(s, Vector2i(W.WEST - 3, 2))
	s.step(20)
	assert_eq(p.state, CollapsePoints.State.CREAKING)
	var creaking: Dictionary = _tell(ann).duplicate()
	for key: String in ["size_or_kind", "level", "position", "facing", "in_hand", "flags"]:
		assert_eq(var_to_str(creaking.get(key, null)), var_to_str(before.get(key, null)), "creaking, its %s is as it was" % key)
	assert_gt(W.until_fallen(s, p.id), 0)
	s.step(6)
	assert_true(_tell(ann).is_empty(), "fallen, the tell is gone")
	assert_true(lamp.burning())
	for v: Dictionary in audit.violations.slice(0, 8):
		gut.p("VIOLATION %s" % v)
	assert_eq(audit.violation_count, 0, "nothing the miner could not perceive")
