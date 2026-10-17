extends "res://tests/scenario/kit/scenario_test.gd"
## HAZ-03 (Gameplay §12.5, §12.6): a point falls once a run, and the fall stands. Its cell evicted
## and committed again, or its run resumed from a save, it comes back fallen through GEN-13's FALL
## record: no noise, no injury, no erasure (chalk laid beside it afterwards stays), never armed
## again, and the map table untouched.

const W = preload("res://tests/unit/hazards/collapse_world.gd")
const S = preload("res://tests/scenario/net/save_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


## The point fallen, Ann well east of it (cell (1, 0)), chalk beside the rubble, a map-table record.
func _fallen(cfg: Dictionary) -> Array:
	var s: Scenario = make(cfg)
	var p: CollapsePoints.Point = W.arm(s)
	var ann: MinerHandle = W.miner_at(s, "ann", Vector2(30.5, 2.5))
	s.run.diff_log.run_section(DiffLog.MAP_TABLE).put("probe", {"strokes": 3})
	W.trigger(s, Vector2i(W.EAST + 2, 2))
	assert_gt(W.until_fallen(s, p.id), 0)
	s.run.chalk.store.put(s.run, Vector2i(W.WEST - 1, 2), ChalkMarks.Surface.FLOOR, ChalkMarks.glyph(ChalkMarks.Kind.CROSS), ann.entity_id)
	s.step(2)
	return [s, p, ann]


func _assert_fallen_quietly(s: Scenario, rubble: Array[Vector2i], ann: int) -> void:
	for t: Vector2i in rubble:
		assert_true(s.mine.native.is_solid(t), "%s still fallen" % t)
	assert_eq(W.events_of(s, NoiseTypes.Type.ROOF_FALL).size(), 0, "no new noise")
	assert_eq(W.events_of(s, NoiseTypes.Type.COLLAPSE_CREAK).size(), 0)
	assert_ne(s.run.chalk.store.glyph_at(Vector2i(W.WEST - 1, 2), ChalkMarks.Surface.FLOOR), 0, "no erasure: the chalk beside it")
	assert_eq(s.run.miner_state.life(ann), MinerTransitions.Life.UPRIGHT, "no injury")
	assert_lte(s.run.miner_state.miner(ann).overlays.hurt_until, s.run.tick)
	assert_true(s.run.collapses.points.is_empty(), "nothing armed")
	assert_eq(s.run.collapses.arm_alternate(s.run, Vector2i.ZERO, 1), 0, "and never armed again")
	var probe: Dictionary = s.run.diff_log.run_section(DiffLog.MAP_TABLE).get_payload("probe")
	assert_eq(Variants.whole(probe.get("strokes", -1)), 3, "the map table untouched")


func test_evicted_and_back_it_is_fallen_quietly() -> void:
	var w: Array = _fallen(W.cfg(3801))
	var s: Scenario = w[0]
	var p: CollapsePoints.Point = w[1]
	var ann: MinerHandle = w[2]
	s.run.noise.event_log.clear()
	assert_true(s.mine.native.unload(Vector2i.ZERO), "its cell leaves")
	s.step(2)
	s.mine.native.commit(CellFile.from_dict(s.fixture.cells[0], "fixture"))
	assert_true(s.mine.native.is_loaded(Vector2i.ZERO), "and comes back, generated standing")
	s.step(3)
	_assert_fallen_quietly(s, p.rubble, ann.entity_id)


func test_resumed_it_is_fallen_quietly() -> void:
	S.clear(3802)
	var cfg: Dictionary = W.cfg(3802)
	cfg["saves"] = true
	var w: Array = _fallen(cfg)
	var s: Scenario = w[0]
	var p: CollapsePoints.Point = w[1]
	var rubble: Array[Vector2i] = p.rubble.duplicate()
	assert_false(s.run.saves.snapshot(s.run).is_empty(), "saved")
	var path: String = S.snapshot_path(s)
	S.kill(s)
	var opened: Dictionary = SaveResume.open_file(path)
	assert_true(Variants.flag(opened["ok"]), str(opened["message"]))
	var again: Dictionary = W.cfg(3802)
	again["saves"] = true
	var b: Scenario = make(again)
	SaveResume.apply(b.run, b.net, opened)
	var back: MinerHandle = b.rejoin("ann")
	b.step(3)
	_assert_fallen_quietly(b, rubble, back.entity_id)


## Saved as it creaks, the resumed run's point creaks on and falls on the tick it would have.
func test_saved_creaking_it_falls_on_time() -> void:
	S.clear(3803)
	var cfg: Dictionary = W.cfg(3803)
	cfg["saves"] = true
	var s: Scenario = make(cfg)
	var p: CollapsePoints.Point = W.arm(s)
	W.miner_at(s, "ann", Vector2(30.5, 2.5))
	W.trigger(s, Vector2i(W.EAST + 2, 2))
	s.step(40)
	assert_eq(p.state, CollapsePoints.State.CREAKING)
	var due: int = p.fall_tick
	assert_false(s.run.saves.snapshot(s.run).is_empty(), "saved mid-creak")
	var path: String = S.snapshot_path(s)
	S.kill(s)
	var b: Scenario = make(cfg.duplicate())
	SaveResume.apply(b.run, b.net, SaveResume.open_file(path))
	b.rejoin("ann")
	var pid: int = b.run.collapses.arm_alternate(b.run, Vector2i.ZERO, 1)
	assert_eq(pid, p.id, "armed again as its cell loads")
	var q: CollapsePoints.Point = b.run.collapses.points[pid]
	assert_eq(q.state, CollapsePoints.State.CREAKING, "still creaking")
	assert_eq(q.fall_tick, due, "on the same clock")
	assert_eq(W.until_fallen(b, pid, 120), due, "it falls on the tick it would have")
