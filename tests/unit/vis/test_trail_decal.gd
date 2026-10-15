extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-10: a dragged-across tile reaches a viewer seeing it at 0.12 or more as a blood decal with its
## direction (8, the drag's heading; the latest wins where trails cross), and not at 0.11; a roof fall
## erases it. The client's TrailDecal reads the direction back.

const B = preload("res://tests/unit/mnr/belt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_eight_directions_by_comparison() -> void:
	var cases: Array = [[Vector2(1, 0), 0], [Vector2(1, 1), 1], [Vector2(0, 1), 2], [Vector2(-1, 1), 3],
		[Vector2(-1, 0), 4], [Vector2(-1, -1), 5], [Vector2(0, -1), 6], [Vector2(1, -1), 7],
		[Vector2(1, 0.3), 0], [Vector2(1, 0.5), 1], [Vector2(0.3, 1), 2]]
	for c: Array in cases:
		var d: Vector2 = c[0]
		var want: int = c[1]
		assert_eq(VisionSystem.trail_direction(Vector2(5, 5), Vector2(5, 5) + d), want, "heading %s" % d)
		assert_lt(TrailDecal.vector_of(want).distance_to(Vector2(cos(want * PI / 4.0), sin(want * PI / 4.0))), 1e-5)


func _frame_tile(s: Scenario, slot: int, t: Vector2i) -> int:
	var f: Dictionary = s.run.vision.frame_for(slot)
	var tiles: Dictionary = f["tiles"]
	var xs: PackedInt32Array = tiles["x"]
	var ys: PackedInt32Array = tiles["y"]
	var decals: PackedByteArray = tiles["decals"]
	for i: int in xs.size():
		if xs[i] == t.x and ys[i] == t.y:
			return decals[i]
	return -1


func test_seen_at_0_12_with_its_direction() -> void:
	var s: Scenario = make({"seed": 991, "fixture": B.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"), {"facing_deg": 0.0})
	ann.brain = null
	var a: Vector2i = s.fixture.spot("a")
	var lit: Vector2i = a + Vector2i(3, 0)
	var dim: Vector2i = a + Vector2i(4, 0)
	s.run.light.grid.add_area("t12", LbLightGrid.COLOUR_AMBER, 0, 0.12, [lit])
	s.run.light.grid.add_area("t11", LbLightGrid.COLOUR_AMBER, 0, 0.11, [dim])
	s.run.vision.mark_trail(lit, 6)
	s.run.vision.mark_trail(lit, 1)  # crossed later: the latest wins
	s.run.vision.mark_trail(dim, 3)
	s.step(2)
	var bits: int = _frame_tile(s, ann.slot, lit)
	assert_ne(bits, -1, "the 0.12 tile is seen")
	assert_eq(bits & TileBits.DECAL_BLOOD, TileBits.DECAL_BLOOD, "with its blood")
	assert_eq(TrailDecal.direction_of(bits), 1, "and the latest direction")
	assert_eq(_frame_tile(s, ann.slot, dim), -1, "at 0.11 nothing reaches her")
	s.run.vision.erase_trail(lit)
	s.step(1)
	assert_eq(_frame_tile(s, ann.slot, lit) & TileBits.DECAL_BLOOD, 0, "a roof fall erases it")
	assert_false(s.run.vision.trails.has(lit))
	# The client reads the direction back.
	var view: ReceivedView = ReceivedView.new()
	view.tiles[lit] = PackedByteArray([40, 1, TileBits.DECAL_BLOOD | (5 << TileBits.DECAL_DIR_SHIFT)])
	var drawn: DrawnSet = DrawnSet.new()
	drawn.build(view, {"position": Vector2(lit), "facing": 0, "lamp": {}}, 0, -1)
	var layer: TrailDecal = TrailDecal.new()
	layer.set_frame(drawn, view, Vector2.ZERO, 64.0)
	assert_eq(layer.smears(), {lit: 5})
	assert_gte(layer.streak_width() * 800.0 / 1080.0, 3.0, "streaks at least 3 px wide at 1280x800")
	assert_false(TrailDecal.colour_at(0.0) == Color(0, 0, 0, TrailDecal.ALPHA), "never pure black")
	layer.free()
