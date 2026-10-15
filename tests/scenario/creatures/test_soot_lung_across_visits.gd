extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-15: the lair's air. A miner 60 s in the lair, out, and back 60 s more catches soot-lung at
## exactly 120 s in all; a cure resets the count; a kept body, lying there, gathers lair time like
## anyone else.

const H = preload("res://tests/scenario/creatures/stythe_hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _lair(s: Scenario) -> StytheLair:
	var lair: StytheLair = s.run.stythe_lair
	var tiles: Array[Vector2i] = []
	for x: int in range(80, 90):
		tiles.append(Vector2i(x, 2))
	lair.set_layout(tiles, tiles)
	return lair


func _has_soot(s: Scenario, miner: int) -> bool:
	return s.run.miner_state.miner(miner).overlays.marks.has(MinerOverlays.SOOT_LUNG)


func test_soot_lung_at_120_s_across_two_visits() -> void:
	var s: Scenario = make({"seed": 1531, "fixture": H.road()})
	var lair: StytheLair = _lair(s)
	var ann: MinerHandle = H.W.miner(s, "ann", Vector2i(70, 2))
	s.step(2)
	var hz: int = roundi(Tuning.f(&"net.tick_hz"))
	s.run.movement.place(s.run, ann.entity_id, Vector2(84.5, 2.5))
	s.step(60 * hz)
	assert_almost_eq(lair.lair_seconds(ann.entity_id), 60.0, 0.11, "a minute in the lair")
	s.run.movement.place(s.run, ann.entity_id, Vector2(70.5, 2.5))
	s.step(30 * hz)
	assert_almost_eq(lair.lair_seconds(ann.entity_id), 60.0, 0.11, "kept while away")
	s.run.movement.place(s.run, ann.entity_id, Vector2(84.5, 2.5))
	var entered: int = s.run.tick
	assert_true(s.run_until(func(sc: Scenario) -> bool: return not sc.run.stythe_lair.soot_lung.is_empty(), 61 * hz))
	var caught: Dictionary = lair.soot_lung[0]
	var in_lair: float = lair.lair_seconds(ann.entity_id)
	assert_eq(in_lair, 120.0, "caught at exactly 120 s in all")
	assert_almost_eq(float(int(Variants.number(caught["tick"])) - entered) / hz, 60.0, 0.11, "60 s into the second visit")
	s.step(2)
	assert_true(_has_soot(s, ann.entity_id), "soot-lung")
	s.run.miner_state.cure_mark(ann.entity_id, MinerOverlays.SOOT_LUNG)
	s.step(2)
	assert_false(_has_soot(s, ann.entity_id), "cured")
	assert_lt(lair.lair_seconds(ann.entity_id), 1.0, "a cure resets the count")


func test_a_kept_body_gathers_lair_time() -> void:
	var s: Scenario = make({"seed": 1532, "fixture": H.road()})
	var lair: StytheLair = _lair(s)
	var bob: MinerHandle = H.W.miner(s, "bob", Vector2i(83, 2))
	s.step(2)
	assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.MOTH_SMOTHER))
	var hz: int = roundi(Tuning.f(&"net.tick_hz"))
	s.step(30 * hz)
	assert_almost_eq(lair.lair_seconds(bob.entity_id), 30.0, 0.2, "lying unconscious, it counts the same")
