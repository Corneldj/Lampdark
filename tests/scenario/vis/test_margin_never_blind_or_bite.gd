extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-04: the hidden margin is 2 tiles of geometry and 1 of entities beyond the lit edge of the
## miner's own light, inside the cone; never the blind area, a bite or an entity in one; none for
## a shuttered, slotted or spent lamp; guttered, it follows the server's radius on both sides.

const M = preload("res://tests/scenario/vis/margin_world.gd")
const LAMP_AT: Vector2 = Vector2(8.5, 4.5)


func before_all() -> void:
	assert_true(Tuning.load_server())


func _setup(seed_value: int) -> Array:
	var s: Scenario = make({"seed": seed_value, "fixture": M.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"), {"facing_deg": 0.0})
	ann.at(0).face(0.0)
	var lamp: int = M.lamp(s, ann.entity_id, LAMP_AT)
	return [s, ann, lamp]


func _in_cone(s: Scenario, ann: MinerHandle, p: Vector2) -> bool:
	return s.run.vision.native.in_cone(ann.slot, p)


## NET-12: inside the cone widened by the turn band (what the miner can turn into before a frame
## arrives); beyond it, the rest of the blind area, nothing is ever prefetched. Like VIS-03, a
## moth counts by its 2x2 footprint's tile centres.
func _in_turn_band(s: Scenario, ann: MinerHandle, p: Vector2) -> bool:
	var at: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	var facing: Vector2 = ViewGeometry.facing_vector(s.run.movement.facing_of(ann.slot))
	var limit: float = Tuning.f(&"vision.cone_deg") / 2.0 + VisionSystem.turn_band_deg(0.0) + 0.5
	var lo: Vector2i = Vector2i(floori(p.x - 0.5), floori(p.y - 0.5))
	for dy: int in 2:
		for dx: int in 2:
			var c: Vector2 = Vector2(lo.x + dx, lo.y + dy) + Vector2(0.5, 0.5)
			if _in_cone(s, ann, c) or at.distance_to(c) <= 0.5:
				return true
			if rad_to_deg(absf(facing.angle_to(c - at))) <= limit:
				return true
	return false


func test_normal_lamp_bands() -> void:
	var setup: Array = _setup(41)
	var s: Scenario = setup[0]
	var ann: MinerHandle = setup[1]
	var near: SimEntity = s.run.registry.create(WorldIds.EntityKind.MOTH, Vector2(11.5, 4.5))
	var margin: SimEntity = s.run.registry.create(WorldIds.EntityKind.MOTH, Vector2(13.5, 4.5))
	var far: SimEntity = s.run.registry.create(WorldIds.EntityKind.MOTH, Vector2(15.5, 4.5))
	var behind: SimEntity = s.run.registry.create(WorldIds.EntityKind.MOTH, Vector2(3.5, 4.5))
	s.step(4)
	var frame: Dictionary = s.run.vision.frame_for(ann.slot)
	var tiles: Dictionary = M.margin_tiles(frame)
	assert_gt(tiles.size(), 10, "a margin arrives")
	for raw: Variant in tiles.keys():
		var t: Vector2i = raw
		var d: float = LAMP_AT.distance_to(M.centre(t))
		assert_true(d > 4.0 and d <= 6.0, "geometry margin at 4 < d <= 6: %s at %.2f" % [t, d])
		assert_true(_in_cone(s, ann, M.centre(t)), "inside the cone: %s" % t)
	for y: int in range(1, 8):
		for x: int in range(1, 23):
			var t: Vector2i = Vector2i(x, y)
			var d: float = LAMP_AT.distance_to(M.centre(t))
			if d > 4.0 and d <= 6.0 and _in_cone(s, ann, M.centre(t)):
				assert_true(tiles.has(t), "every dark tile of the band in the cone is sent: %s" % t)
	assert_eq(M.margin_positions(frame), [margin.position] as Array[Vector2], "only the entity at 5 tiles is a margin token")
	var levels: Dictionary = {}
	for raw: Variant in ann.capture.entities_visible(s.run.tick).values():
		var e: Dictionary = raw
		var p: Vector2 = e["position"]
		levels[p.snapped(Vector2(0.01, 0.01))] = int(Variants.number(e["level"]))
	var hidden_level: int = int(Variants.number(levels.get(Vector2(13.5, 4.5), 0)))
	var lit_level: int = int(Variants.number(levels.get(Vector2(11.5, 4.5), 0)))
	assert_eq(hidden_level, 3, "the client holds it hidden")
	assert_true(lit_level == 1 or lit_level == 2, "the lit one is seen, not hidden")
	assert_false(levels.has(Vector2(15.5, 4.5)), "nothing farther arrives")
	assert_false(levels.has(Vector2(3.5, 4.5)), "nothing from behind arrives")
	assert_eq(s.run.vision.native.sees_entity(ann.slot, far.id), LbVision.LEVEL_NONE)
	assert_eq(s.run.vision.native.sees_entity(ann.slot, behind.id), LbVision.LEVEL_NONE)
	assert_ne(s.run.vision.native.sees_entity(ann.slot, near.id), LbVision.LEVEL_NONE)


func test_never_a_bite_or_an_entity_in_one() -> void:
	var setup: Array = _setup(42)
	var s: Scenario = setup[0]
	var ann: MinerHandle = setup[1]
	s.run.registry.create(WorldIds.EntityKind.MOTH, Vector2(13.5, 4.5))
	var bite: Array = [Vector2i(13, 4), Vector2i(13, 3), Vector2i(14, 5)]
	s.step(2)
	s.run.vision.native.set_bite_tiles(ann.slot, bite)
	s.step(2)
	var frame: Dictionary = s.run.vision.frame_for(ann.slot)
	for t: Vector2i in bite:
		assert_false(M.margin_tiles(frame).has(t), "a bite tile is omitted: %s" % t)
	assert_eq(M.margin_positions(frame).size(), 0, "an entity standing in a bite is omitted")


func test_no_edge_no_margin() -> void:
	var setup: Array = _setup(43)
	var s: Scenario = setup[0]
	var ann: MinerHandle = setup[1]
	var lamp: int = setup[2]
	s.run.registry.create(WorldIds.EntityKind.MOTH, Vector2(13.5, 4.5))
	s.step(2)
	assert_gt(M.margin_tiles(s.run.vision.frame_for(ann.slot)).size(), 0)
	s.run.light.grid.update_point(lamp, LAMP_AT, 0.0, 1.0)
	s.step(2)
	assert_eq(M.margin_tiles(s.run.vision.frame_for(ann.slot)).size(), 0, "shuttered or slotted (no pool): no margin")
	assert_eq(M.margin_positions(s.run.vision.frame_for(ann.slot)).size(), 0)
	s.run.light.grid.remove_source(lamp)
	var bob: MinerHandle = s.add_miner("bob", s.fixture.spot("b"))
	M.lamp(s, bob.entity_id, LAMP_AT)
	s.step(3)
	assert_eq(M.margin_tiles(s.run.vision.frame_for(ann.slot)).size(), 0, "out: a teammate's lamp beside her gives her no margin")
	assert_eq(M.margin_positions(s.run.vision.frame_for(ann.slot)).size(), 0)


func test_guttered_margin_and_predicted_pool() -> void:
	var setup: Array = _setup(44)
	var s: Scenario = setup[0]
	var ann: MinerHandle = setup[1]
	var lamp: int = setup[2]
	s.enable_prediction(ann)
	s.step(6)
	assert_almost_eq(Variants.number(ann.prediction.lamp()["radius"]), 4.0, 0.01, "the predicted pool is the server's")
	s.run.light.grid.set_radius_modifier(lamp, 0.7, "gutter")
	var changed: int = s.run.tick
	s.step(1)
	var tiles: Dictionary = M.margin_tiles(s.run.vision.frame_for(ann.slot))
	assert_gt(tiles.size(), 0)
	var nearest: float = 99.0
	for raw: Variant in tiles.keys():
		var t: Vector2i = raw
		var d: float = LAMP_AT.distance_to(M.centre(t))
		nearest = minf(nearest, d)
		assert_true(d > 2.8 and d <= 4.8, "the margin begins at 2.8 tiles: %.2f" % d)
	assert_lt(nearest, 3.5, "and reaches in to it")
	# Each frame: the server's radius it carries, and the client's predicted pool once decoded.
	var seen: Dictionary = {}
	var hook: Callable = ann.capture.on_decoded
	ann.capture.on_decoded = func(decoded: FrameDecoder.Decoded) -> void:
		hook.call(decoded)
		seen[decoded.tick] = [Variants.number(decoded.view.own["lamp_radius"]), Variants.number(ann.prediction.lamp()["radius"])]
	s.step(4)
	var first: int = -1
	for raw: Variant in seen.keys():
		var t: int = raw
		var pair: Array = seen[t]
		var server_radius: float = pair[0]
		var predicted: float = pair[1]
		assert_almost_eq(predicted, server_radius, 0.0001, "frame %d: the predicted pool is the server's" % t)
		if absf(server_radius - 2.8) <= 1.0 / 32.0 and (first < 0 or t < first):
			first = t
	gut.p("guttered at tick %d; first frame carrying it: %d; the client's pool matched on decoding it" % [changed, first])
	assert_between(first, changed, changed + 1, "the guttered radius rides the next frame")


func test_property_raised_margins_never_blind_or_bite() -> void:
	var setup: Array = _setup(45)
	var s: Scenario = setup[0]
	var ann: MinerHandle = setup[1]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 45
	for i: int in 10:
		s.run.registry.create(WorldIds.EntityKind.MOTH, Vector2(rng.randf_range(1.2, 22.8), rng.randf_range(1.2, 7.8)))
	s.step(2)
	var checked: int = 0
	for trial: int in 40:
		var geometry: float = rng.randf_range(1.0, 10.0)
		s.run.vision.native.set_params({"margin_geometry": geometry, "margin_entity": rng.randf_range(0.5, geometry)})
		var bite: Array = []
		for b: int in 6:
			bite.append(Vector2i(rng.randi_range(1, 22), rng.randi_range(1, 7)))
		s.run.vision.native.set_bite_tiles(ann.slot, bite)
		ann.at(s.run.tick).face(rng.randf_range(0.0, 360.0))
		s.step(2)
		var frame: Dictionary = s.run.vision.frame_for(ann.slot)
		for raw: Variant in M.margin_tiles(frame).keys():
			var t: Vector2i = raw
			assert_true(_in_cone(s, ann, M.centre(t)), "never the blind area: %s" % t)
			assert_false(bite.has(t), "never a bite: %s" % t)
			checked += 1
		for p: Vector2 in M.margin_positions(frame):
			assert_true(_in_turn_band(s, ann, p), "no entity behind, beyond the turn band (NET-12)")
			assert_false(bite.has(Vector2i(floori(p.x), floori(p.y))), "no entity in a bite")
	assert_gt(checked, 200, "the property saw margins")
	s.run.vision.native.set_params({"margin_geometry": Tuning.f(&"vision.margin_geometry_tiles"), "margin_entity": Tuning.f(&"vision.margin_entity_tiles")})
