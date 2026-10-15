extends "res://tests/scenario/kit/scenario_test.gd"
## SND-12: POINT lights one tile to at least 0.30 for 2 s, then clears it; the tile is along the
## facing, never beyond 6 tiles, and never past rock (the signaller's line of sight).

const W = preload("res://tests/unit/sound/signal_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _point(s: Scenario, ann: MinerHandle) -> Dictionary:
	W.signal_press(s, ann, LampSignalKind.Kind.POINT)
	s.step(6)
	return Variants.dict(s.run.lamp_signals.active.get(ann.entity_id, {}))


func test_lit_for_two_seconds_at_six_tiles() -> void:
	var s: Scenario = make({"seed": 1111, "fixture": W.road()})
	var ann: MinerHandle = W.miner(s, "ann", s.fixture.spot("a"), 0.0)
	var a: Dictionary = _point(s, ann)
	assert_false(a.is_empty(), "pointing")
	var t: Vector2i = a["point_tile"]
	var me: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	assert_eq(t, Vector2i(me + Vector2(6.0, 0.0)), "6 tiles along the facing")
	assert_gte(s.run.light.light_at(t), 0.30, "lit to 0.30 or more")
	var spot: int = int(Variants.number(a["spot"]))
	assert_true(s.run.light.grid.has_source(spot))
	var lit_ticks: int = 0
	for _i: int in 60:
		if s.run.light.grid.has_source(spot):
			lit_ticks += 1
		s.step(1)
	gut.p("the spot lasted %d more ticks" % lit_ticks)
	assert_false(s.run.light.grid.has_source(spot), "then cleared")
	assert_between(lit_ticks + 6, 38, 42, "2 s in all")


func test_stopped_by_rock() -> void:
	var s: Scenario = make({"seed": 1112, "fixture": W.road(50, 4)})
	var ann: MinerHandle = W.miner(s, "ann", s.fixture.spot("a"), 0.0)
	var a: Dictionary = _point(s, ann)
	var me: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	var t: Vector2i = a["point_tile"]
	assert_eq(t, Vector2i(me) + Vector2i(3, 0), "the last tile before the rib, in her sight")
