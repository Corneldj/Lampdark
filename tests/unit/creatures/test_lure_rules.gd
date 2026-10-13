extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-09's lures, ring by ring: in ring 1 a 14 np bang 7 tiles off frees the victim and the hunt
## moves to the banger; a stone with nobody beside it frees the victim and the hunt is on nobody;
## in ring 0 a bang 9 tiles away is beyond its hearing and fails.

const W = preload("res://tests/scenario/creatures/hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_each() -> void:
	super.after_each()
	Tuning.clear_dev_overrides()


func test_bang_moves_the_hunt() -> void:
	W.ring(1)
	var s: Scenario = make({"seed": 50, "fixture": W.road()})
	var r: Array = W.pinned(s)
	var ann: MinerHandle = r[0]
	var t: Tapper = r[1]
	var cid: MinerHandle = s.add_miner("cid", Vector2i(17, 5))
	s.step(2)
	W.bang(s, Vector2i(17, 5), 14.0, cid.entity_id)
	s.step(3)
	assert_eq(W.life(s, ann.entity_id), MinerTransitions.Life.UPRIGHT, "the lure drops the victim")
	assert_eq(s.run.creatures.gate.target_of(t), cid.entity_id, "the banger becomes its target")
	assert_eq(t.state.name, &"approach")


func test_stone_lures_to_nobody() -> void:
	W.ring(1)
	var s: Scenario = make({"seed": 51, "fixture": W.road()})
	var r: Array = W.pinned(s)
	var ann: MinerHandle = r[0]
	var t: Tapper = r[1]
	s.step(2)
	W.bang(s, Vector2i(18, 5), 14.0, 0)
	s.step(3)
	assert_eq(W.life(s, ann.entity_id), MinerTransitions.Life.UPRIGHT)
	assert_eq(s.run.creatures.gate.target_of(t), 0, "the hunt is on nobody")


func test_ring_zero_too_far() -> void:
	var s: Scenario = make({"seed": 52, "fixture": W.road()})
	assert_eq(WorldCoords.ring_of_point(Vector2(10.5, 4.5)), 0)
	var r: Array = W.pinned(s)
	var ann: MinerHandle = r[0]
	s.step(2)
	W.bang(s, Vector2i(19, 5), 14.0, 0)
	s.step(3)
	assert_eq(W.life(s, ann.entity_id), MinerTransitions.Life.GRABBED, "9 tiles in ring 0: unheard, the lure fails")
