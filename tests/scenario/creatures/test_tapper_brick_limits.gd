extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-08: the Tapper occupies rock (and the floor it passes beneath), never brick, moving at
## 3.5 tiles/s; noise from the brick-lined room never reaches it through the brick.

const T = preload("res://tests/scenario/creatures/tapper_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_brick() -> void:
	var s: Scenario = make({"seed": 24, "fixture": T.block()})
	var t: Tapper = T.tapper(s, Vector2i(20, 8))
	var tiles: Dictionary = {}
	var fastest: Array[float] = [0.0]
	var last: Array[Vector2] = [t.position(s.run)]
	s.on_tick = func(sc: Scenario) -> void:
		tiles[t.tile(sc.run)] = true
		fastest[0] = maxf(fastest[0], t.position(sc.run).distance_to(last[0]))
		last[0] = t.position(sc.run)
		if sc.run.tick % 20 == 0:
			# Inside the brick-lined room (never reaches it) and out on the road to the east.
			sc.run.noise.emit(NoiseTypes.Type.HAMMER, Vector2i(45, 2), {"level_np": 30.0})
			sc.run.noise.emit(NoiseTypes.Type.RAIL_BANG, Vector2i(36, 4), {"level_np": 30.0})
	s.step(600)
	for raw: Variant in tiles.keys():
		var tile: Vector2i = raw
		var m: int = s.run.mine.native.effective_material(tile)
		assert_ne(m, WorldIds.TileMaterial.BRICK, "never brick: %s" % tile)
		assert_false(tile.y >= 2 and tile.y <= 3 and tile.x >= 41 and tile.x <= 48, "never in the brick-lined room")
	assert_almost_eq(fastest[0], 3.5 / 20.0, 0.01, "3.5 tiles/s")
	assert_gt(tiles.size(), 10, "it moved toward the noise")
	assert_eq(s.run.creatures.teleport_violations, 0)
