extends "res://tests/scenario/kit/scenario_test.gd"
## HAZ-03 (Gameplay §12.5; GDD §15.8): a roof brought down by a running step takes whoever is under
## it 100 ticks later, where they stand then. A carrier under it sets the body down first; both end on
## open floor, the carrier unconscious beside the body. A creature on the rubble (the Stythe's
## stand-in) is moved off it unharmed (Proposed), a burning lamp lying there too, a stretcher whose
## end it caught lies clear of the rock, and a miner at its edge is pinned. Nothing is left on a
## fallen tile.

const W = preload("res://tests/unit/hazards/collapse_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_under_it_at_its_edge_and_beside_it() -> void:
	var s: Scenario = make(W.cfg(3701))
	var p: CollapsePoints.Point = W.arm(s)
	# The creature first: none spawns where a miner sees.
	var stythe: int = s.place_stand_in(WorldIds.EntityKind.STYTHE, Vector2i(16, 1))
	assert_gt(stythe, 0)
	var ann: MinerHandle = W.miner_at(s, "ann", Vector2(12.5, 2.5))
	var bob: MinerHandle = W.miner_at(s, "bob", Vector2(13.5, 2.5))
	var cat: MinerHandle = W.miner_at(s, "cat", Vector2(W.EAST + 0.5, 1.5))
	s.step(1)
	W.L.lit_in_hand(s, ann)
	assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.BLAST))
	s.step(2)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 42)
	s.step(1)
	assert_true(s.run.inventory.start_action(s.run, s.run.carry.lift_action(s.run, ann.entity_id, bob.entity_id)))
	s.step(45)
	assert_true(s.run.carry.is_carrying(ann.entity_id), "Ann carries Bob")
	s.run.movement.place(s.run, ann.entity_id, Vector2(12.5, 2.5))
	var lamp: GauzeLamp = s.run.lamps.create(s.run, 1.0, 3, true, LampRules.WICK_NORMAL, Vector2(15.5, 3.5))
	# A stretcher lying east-west with its east end on the rubble's first column.
	var stretcher: int = s.run.inventory.world.put(s.run, s.run.inventory.world.make(ItemKinds.Kind.STRETCHER), Vector2(14.6, 1.5))
	W.trigger(s, Vector2i(W.WEST - 3, 2))
	assert_eq(p.state, CollapsePoints.State.CREAKING)
	# She walks under it as it creaks, and stands there.
	s.run.movement.place(s.run, ann.entity_id, Vector2(16.5, 2.5))
	assert_gt(W.until_fallen(s, p.id), 0, "it falls")
	s.step(2)
	assert_eq(s.run.miner_state.life(ann.entity_id), MinerTransitions.Life.UNCONSCIOUS, "under it: unconscious")
	assert_false(s.run.carry.is_carrying(ann.entity_id), "the body set down first")
	assert_eq(s.run.miner_state.life(bob.entity_id), MinerTransitions.Life.UNCONSCIOUS)
	for h: MinerHandle in [ann, bob]:
		var at: Vector2 = s.run.registry.get_entity(h.entity_id).position
		assert_false(s.mine.native.is_solid(Vector2i(floori(at.x), floori(at.y))), "%s on open floor" % h.name)
	var a: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	assert_lt(a.distance_to(s.run.registry.get_entity(bob.entity_id).position), 3.0, "beside the body she carried")
	assert_true(s.run.registry.has(stythe), "the creature unharmed")
	var c: Vector2 = s.run.registry.get_entity(stythe).position
	assert_false(s.mine.native.is_solid(Vector2i(floori(c.x), floori(c.y))), "and moved off the rubble")
	assert_true(lamp.burning(), "the lamp still burns")
	assert_false(p.rubble.has(Vector2i(floori(lamp.at.x), floori(lamp.at.y))), "off the rubble")
	assert_true(s.run.holds.caught.has(cat.entity_id), "at its edge: pinned")
	var it: Item = s.run.inventory.world.item_at(stretcher)
	var pose: Vector2 = s.run.registry.get_entity(stretcher).position
	var h: int = int(Variants.number(it.state.get("heading", 0)))
	var solid: Callable = func(t: Vector2i) -> bool: return s.mine.native.is_solid(t)
	assert_false(LoadSegment.make(it.kind, pose, h).collides(pose.x, pose.y, h, solid), "the stretcher lies clear of the rock")
	for id: int in s.run.registry.ids():
		assert_false(p.rubble.has(s.run.registry.get_entity(id).tile()), "nothing left on a fallen tile (entity %d)" % id)
