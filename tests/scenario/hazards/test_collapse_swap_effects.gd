extends "res://tests/scenario/kit/scenario_test.gd"
## HAZ-03 (Gameplay §12.5, §6.1, §6.6; GDD §15.8): in the fall's one tick, before that tick's
## visibility stage, the swap carries everything with it. Sound reroutes (the road is cut: no path
## through); light stops at the rubble; a miner's sight line through it is gone from that tick's
## frame. Chalk and blood on the fallen tiles are erased, and nowhere else; LFT-12's lines hear the
## fall on exactly its tiles (the `fell` signal stands in for PhoneLines.on_tiles_fallen).

const W = preload("res://tests/unit/hazards/collapse_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_everything_follows_the_swap_in_its_tick() -> void:
	var s: Scenario = make(W.cfg(3601))
	var p: CollapsePoints.Point = W.arm(s)
	# A lamp lying just west of the rubble, light beyond it to the east, Ann west looking east.
	s.run.lamps.create(s.run, 1.0, 3, true, LampRules.WICK_UP, Vector2(14.5, 2.5))
	var east: Array = []
	for x: int in range(21, 26):
		for y: int in range(1, 4):
			east.append(Vector2i(x, y))
	s.run.light.grid.add_area("emergency", LbLightGrid.COLOUR_WHITE, 0, 0.6, east)
	var ann: MinerHandle = W.miner_at(s, "ann", Vector2(12.5, 2.5))
	ann.at(s.run.tick).face(0.0)
	# Chalk and blood on the rubble, and beside it.
	s.run.chalk.store.put(s.run, Vector2i(16, 2), ChalkMarks.Surface.FLOOR, ChalkMarks.glyph(ChalkMarks.Kind.CROSS), ann.entity_id)
	s.run.chalk.store.put(s.run, Vector2i(11, 1), ChalkMarks.Surface.FLOOR, ChalkMarks.glyph(ChalkMarks.Kind.DIGIT_3), ann.entity_id)
	s.run.stythe_lair.trail.mark(Vector2i(16, 1), 2)
	s.run.stythe_lair.trail.mark(Vector2i(10, 2), 2)
	var heard: Array = []
	s.run.collapses.fell.connect(func(pid: int, cell: Vector2i, tiles: Array[Vector2i]) -> void: heard.append([pid, cell, tiles]))
	s.step(6)
	var across: float = s.run.road_graph.graph.path_cost(Vector2i(12, 2), Vector2i(20, 2), RoadGraphService.MODE_AIR, 50.0)
	assert_between(across, 7.9, 8.1, "the road open: 8 tiles by path")
	assert_gt(s.run.light.grid.value_at(Vector2(19.5, 2.5)), 0, "the lying lamp lights past the point")
	assert_true(_sees(s, ann, Vector2i(22, 2)), "Ann sees down the road")
	W.trigger(s, Vector2i(W.WEST - 2, 2))
	var fell_at: int = W.until_fallen(s, p.id)
	assert_gt(fell_at, 0)
	# That very tick:
	assert_eq(s.run.road_graph.graph.path_cost(Vector2i(12, 2), Vector2i(20, 2), RoadGraphService.MODE_AIR, 50.0), -1.0,
		"sound reroutes: the road is cut")
	assert_eq(s.run.light.grid.value_at(Vector2(19.5, 2.5)), 0, "light stops at the rubble")
	assert_false(_sees(s, ann, Vector2i(22, 2)), "the sight line is gone from this tick's frame")
	assert_eq(s.run.chalk.store.glyph_at(Vector2i(16, 2), ChalkMarks.Surface.FLOOR), 0, "chalk on the rubble erased")
	assert_ne(s.run.chalk.store.glyph_at(Vector2i(11, 1), ChalkMarks.Surface.FLOOR), 0, "chalk beside it kept")
	assert_eq(s.run.stythe_lair.trail.direction_at(Vector2i(16, 1)), -1, "blood on the rubble erased")
	assert_false(s.run.vision.trails.has(Vector2i(16, 1)), "and its smear")
	assert_eq(s.run.stythe_lair.trail.direction_at(Vector2i(10, 2)), 2, "blood beside it kept")
	assert_eq(heard.size(), 1, "the lines hear it once")
	var got: Array = heard[0]
	var cell: Vector2i = got[1]
	var tiles: Array[Vector2i] = got[2]
	assert_eq(Variants.whole(got[0]), p.id)
	assert_eq(cell, Vector2i.ZERO)
	assert_eq(tiles, p.rubble, "on exactly its tiles")


static func _sees(s: Scenario, h: MinerHandle, tile: Vector2i) -> bool:
	var tiles: Dictionary = Variants.dict(s.run.vision.frame_for(h.slot).get("tiles", {}))
	var xs: PackedInt32Array = tiles.get("x", PackedInt32Array())
	var ys: PackedInt32Array = tiles.get("y", PackedInt32Array())
	for i: int in xs.size():
		if xs[i] == tile.x and ys[i] == tile.y:
			return true
	return false
