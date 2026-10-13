extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-02: a gate never shuts while any body overlaps its doorway: a miner (even only partly, or
## fallen), Bess or a creature. The lever action then jams: it completes, the gate stays open and
## no clang sounds. Loose items on the doorway go to their nearer side at a shut flip.

const C = preload("res://tests/scenario/basecamp/camp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


## Base camp with the west gate open (adopted from the tiles) and ann on its inside lever.
func _open_west(run_seed: int) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	var west: Gate = camp.gate_system.gate("west")
	s.run.mine.native.set_barrier(Vector2i.ZERO, west.barrier, true)
	var ann: MinerHandle = s.add_miner("ann", C.lever(s, "west", "inside"))
	s.step(2)
	assert_true(west.open)
	return [s, camp, west, ann]


func _shut_attempt(s: Scenario, ann: MinerHandle) -> void:
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 31)
	s.step(50)


func test_miner_in_doorway_jams_the_lever() -> void:
	var parts: Array = _open_west(21)
	var s: Scenario = parts[0]
	var camp: BaseCampState = parts[1]
	var west: Gate = parts[2]
	var ann: MinerHandle = parts[3]
	s.add_miner("bob", west.middle())
	s.step(2)
	var jams: Array[int] = []
	camp.gate_system.jammed.connect(func(_side: String) -> void: jams.append(s.run.tick))
	_shut_attempt(s, ann)
	assert_eq(jams.size(), 1, "the action completes and jams")
	assert_true(west.open, "never shuts on anyone")
	assert_eq(C.clangs(s).size(), 0, "a jam makes no sound: nothing moved")
	assert_eq(camp.gate_system.diff_log.size(), 0)
	assert_true(west.actions.is_empty())


func test_partial_overlap_counts() -> void:
	var parts: Array = _open_west(22)
	var s: Scenario = parts[0]
	var west: Gate = parts[2]
	var ann: MinerHandle = parts[3]
	# Standing on the inside floor with the edge of the body over the doorway line.
	var edge: float = Tuning.f(&"movement.body_radius") * 0.5
	var inner: Vector2 = Vector2(west.middle() - west.outward) + Vector2(0.5, 0.5) + Vector2(west.outward) * (0.5 - edge)
	var bob: MinerHandle = s.add_miner("bob", west.middle() - west.outward)
	s.run.registry.move(bob.entity_id, inner)
	s.run.movement.miner(bob.slot).state.x = inner.x
	s.run.movement.miner(bob.slot).state.y = inner.y
	assert_true(west.overlaps(inner, Tuning.f(&"movement.body_radius")))
	assert_false(west.overlaps(Vector2(west.middle() - west.outward * 2) + Vector2(0.5, 0.5), Tuning.f(&"movement.body_radius")))
	_shut_attempt(s, ann)
	assert_true(west.open, "a body partly over the doorway still holds it")


func test_fallen_bess_and_creature_hold_it() -> void:
	for kind: WorldIds.EntityKind in [WorldIds.EntityKind.BESS, WorldIds.EntityKind.MOTH]:
		var parts: Array = _open_west(23 + kind)
		var s: Scenario = parts[0]
		var west: Gate = parts[2]
		var ann: MinerHandle = parts[3]
		var body: int = C.place_body(s, kind, Vector2(west.tiles[0]) + Vector2(0.5, 0.5))
		_shut_attempt(s, ann)
		assert_true(west.open, "%s in the doorway" % WorldIds.EntityKind.find_key(kind))
		s.run.registry.destroy(body)
		_shut_attempt(s, ann)
		assert_false(west.open, "clear: it shuts")
	var parts2: Array = _open_west(29)
	var s2: Scenario = parts2[0]
	var west2: Gate = parts2[2]
	var ann2: MinerHandle = parts2[3]
	var bob: MinerHandle = s2.add_miner("bob", west2.middle())
	s2.step(1)
	s2.run.miner_state.fall_unconscious(bob.entity_id, "test")
	s2.step(1)
	assert_eq(s2.run.miner_state.life(bob.entity_id), MinerTransitions.Life.UNCONSCIOUS)
	_shut_attempt(s2, ann2)
	assert_true(west2.open, "the fallen are anyone")


func test_items_move_to_their_nearer_side() -> void:
	var parts: Array = _open_west(31)
	var s: Scenario = parts[0]
	var west: Gate = parts[2]
	var ann: MinerHandle = parts[3]
	var t0: Vector2i = west.tiles[0]
	var t2: Vector2i = west.tiles[2]
	var inner: int = C.place_body(s, WorldIds.EntityKind.ITEM, Vector2(t0) + Vector2(0.5, 0.5) - Vector2(west.outward) * 0.3)
	var outer: int = C.place_body(s, WorldIds.EntityKind.ITEM, Vector2(t2) + Vector2(0.5, 0.5) + Vector2(west.outward) * 0.3)
	_shut_attempt(s, ann)
	assert_false(west.open, "items do not hold a gate")
	assert_eq(s.run.registry.get_entity(inner).tile(), t0 - west.outward, "to the inside")
	assert_eq(s.run.registry.get_entity(outer).tile(), t2 + west.outward, "to the road")
