extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-04: is_seen_or_margin_of_any (CRT-01's spawn guard) is true for every margin tile of every
## miner and every seen tile, and false for a tile in no miner's seen set or margin.

const M = preload("res://tests/scenario/vis/margin_world.gd")
const W = preload("res://tests/scenario/vis/vis_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_every_margin_tile_is_guarded() -> void:
	var s: Scenario = make({"seed": 61, "fixture": M.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"), {"facing_deg": 0.0})
	var bob: MinerHandle = s.add_miner("bob", s.fixture.spot("b"), {"facing_deg": 90.0})
	var ann_lamp: int = M.lamp(s, ann.entity_id, Vector2(8.5, 4.5))
	var bob_lamp: int = M.lamp(s, bob.entity_id, Vector2(3.5, 1.5), 3.0)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 61
	var margins: int = 0
	var open_checked: int = 0
	for trial: int in 30:
		ann.at(s.run.tick).face(rng.randf_range(0.0, 360.0))
		bob.at(s.run.tick).face(rng.randf_range(0.0, 360.0))
		s.run.light.grid.update_point(ann_lamp, Vector2(8.5, 4.5), rng.randf_range(2.0, 5.5), 1.0)
		s.run.light.grid.update_point(bob_lamp, Vector2(3.5, 1.5), rng.randf_range(2.0, 5.5), 1.0)
		s.step(2)
		var guarded: Dictionary = {}
		for h: MinerHandle in [ann, bob]:
			var frame: Dictionary = s.run.vision.frame_for(h.slot)
			for raw: Variant in M.margin_tiles(frame).keys():
				var t: Vector2i = raw
				assert_true(s.run.vision.native.is_seen_or_margin_of_any(t), "%s's margin tile %s is guarded" % [h.name, t])
				guarded[t] = true
				margins += 1
			for raw: Variant in W.tiles(frame).keys():
				var t: Vector2i = raw
				assert_true(s.run.vision.native.is_seen_or_margin_of_any(t), "%s's seen tile %s is guarded" % [h.name, t])
				guarded[t] = true
		for y: int in range(1, 8):
			for x: int in range(1, 23):
				var t: Vector2i = Vector2i(x, y)
				if not guarded.has(t):
					assert_false(s.run.vision.native.is_seen_or_margin_of_any(t), "%s, in no set, is free to spawn on" % t)
					open_checked += 1
	assert_gt(margins, 300, "margins were checked")
	assert_gt(open_checked, 300, "free tiles were checked")
