extends "res://tests/scenario/kit/scenario_test.gd"
## HAZ-03 (Gameplay §12.5, §8.2; GDD §15.8): who a roof fall takes, by the distance from each body's
## centre to the nearest fallen tile as it falls. At 0 (on the rubble): unconscious, on the nearer
## open tile with the lamp beside them; at 0.8: Caught under a timber pin; at 1.5: Hurt; at 2.5:
## untouched. An unconscious miner at the edge is pinned too, a body on the rubble is moved, and
## nothing (items, lamps, bodies) is left on a fallen tile: nothing is buried.

const W = preload("res://tests/unit/hazards/collapse_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_who_it_takes() -> void:
	var s: Scenario = make(W.cfg(3201))
	var p: CollapsePoints.Point = W.arm(s)
	var on: MinerHandle = W.miner_at(s, "ann", Vector2(16.5, 2.5))
	var edge: MinerHandle = W.miner_at(s, "bob", Vector2(W.EAST + 0.8, 1.5))
	var near: MinerHandle = W.miner_at(s, "cat", Vector2(W.EAST + 1.5, 3.5))
	var far: MinerHandle = W.miner_at(s, "dot", Vector2(W.WEST - 2.5, 2.5))
	var body: MinerHandle = W.miner_at(s, "eve", Vector2(15.5, 3.5))
	var fallen_edge: MinerHandle = W.miner_at(s, "fay", Vector2(W.WEST - 0.5, 1.5))
	var lamp: GauzeLamp = W.L.lit_in_hand(s, on)
	var records: Array[Dictionary] = []
	s.run.falls.fell.connect(func(r: Dictionary) -> void: records.append(r))
	s.step(2)
	assert_true(s.run.falls.fall_unconscious(s.run, body.entity_id, FallCause.Cause.BLAST))
	assert_true(s.run.falls.fall_unconscious(s.run, fallen_edge.entity_id, FallCause.Cause.BLAST))
	var spanner: int = W.B.put(s, ItemKinds.Kind.SPANNER, Vector2i(16, 1))
	s.step(2)
	for h: MinerHandle in [on, edge, near, far, body, fallen_edge]:
		s.run.movement.place(s.run, h.entity_id, _where(h.name))
	assert_eq(CollapsePoints.distance_to(_where("ann"), p.rubble), 0.0)
	assert_almost_eq(CollapsePoints.distance_to(_where("bob"), p.rubble), 0.8, 0.001)
	assert_almost_eq(CollapsePoints.distance_to(_where("cat"), p.rubble), 1.5, 0.001)
	assert_almost_eq(CollapsePoints.distance_to(_where("dot"), p.rubble), 2.5, 0.001)
	s.run.collapses.fall(s.run, p)
	s.step(2)
	var ms: MinerStateSystem = s.run.miner_state
	assert_eq(ms.life(on.entity_id), MinerTransitions.Life.UNCONSCIOUS, "on the rubble: unconscious")
	var at: Vector2 = s.run.registry.get_entity(on.entity_id).position
	assert_false(s.mine.native.is_solid(Vector2i(floori(at.x), floori(at.y))), "on an open tile")
	assert_eq(lamp.place, LampRules.Place.FLOOR, "the lamp dropped")
	assert_lt(lamp.at.distance_to(at), 1.5, "beside her")
	assert_false(s.mine.native.is_solid(Vector2i(floori(lamp.at.x), floori(lamp.at.y))), "on open floor")
	var hers: Array[Dictionary] = records.filter(func(r: Dictionary) -> bool: return int(Variants.number(r["miner_id"])) == on.entity_id)
	assert_eq(hers.size(), 1)
	assert_eq(int(Variants.number(hers[0]["cause"])), FallCause.Cause.ROOF_FALL, "felled by the roof")
	assert_true(s.run.holds.caught.has(edge.entity_id), "within 1 tile: pinned")
	assert_eq(s.run.holds.caught_in(edge.entity_id).kind, CaughtHold.Kind.TIMBER_PIN)
	assert_eq(s.run.holds.caught_in(edge.entity_id).trap_id, p.id)
	assert_eq(ms.life(edge.entity_id), MinerTransitions.Life.CAUGHT)
	assert_gt(ms.miner(near.entity_id).overlays.hurt_until, s.run.tick, "1-2 tiles off: Hurt")
	assert_eq(ms.life(near.entity_id), MinerTransitions.Life.UPRIGHT)
	assert_eq(ms.life(far.entity_id), MinerTransitions.Life.UPRIGHT, "2.5 tiles off: untouched")
	assert_lte(ms.miner(far.entity_id).overlays.hurt_until, s.run.tick, "not Hurt")
	assert_false(s.run.holds.caught.has(far.entity_id))
	assert_true(s.run.holds.caught.has(fallen_edge.entity_id), "an unconscious miner at the edge is pinned too")
	assert_eq(ms.life(body.entity_id), MinerTransitions.Life.UNCONSCIOUS, "a body on the rubble stays a body")
	for id: int in s.run.registry.ids():
		assert_false(p.rubble.has(s.run.registry.get_entity(id).tile()), "nothing left on a fallen tile (entity %d)" % id)
	assert_true(s.run.registry.has(spanner), "the spanner is not buried")


static func _where(name: String) -> Vector2:
	match name:
		"ann":
			return Vector2(16.5, 2.5)
		"bob":
			return Vector2(W.EAST + 0.8, 1.5)
		"cat":
			return Vector2(W.EAST + 1.5, 3.5)
		"dot":
			return Vector2(W.WEST - 2.5, 2.5)
		"eve":
			return Vector2(15.5, 3.5)
		_:
			return Vector2(W.WEST - 0.5, 1.5)
