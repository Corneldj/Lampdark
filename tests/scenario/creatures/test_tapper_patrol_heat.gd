extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-08: Patrol goes toward its heat map's hottest face; with a cold map it rests in rich rock
## (dwelling 30-90 s), and in a relax it moves into rich rock.

const T = preload("res://tests/scenario/creatures/tapper_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_toward_the_hottest_face() -> void:
	var s: Scenario = make({"seed": 25, "fixture": T.block()})
	var t: Tapper = T.tapper(s, Vector2i(10, 15))
	t.hunt.hunt_from_tick = 1 << 40  # patrol alone: CRT-09's hunt would answer the hammer
	s.step(2)
	for i: int in 6:
		s.run.noise.emit(NoiseTypes.Type.HAMMER, Vector2i(25, 4), {"level_np": 30.0})
		s.step(5)
	var hot: Vector2i = t.heat.hottest()
	var start: float = t.position(s.run).distance_to(Vector2(hot))
	s.step(200)
	var end: float = t.position(s.run).distance_to(Vector2(hot))
	gut.p("hottest face %s: %.1f tiles off, then %.1f" % [hot, start, end])
	assert_lt(end, start - 5.0, "it patrols toward the hottest face")
	assert_eq(t.state.name, &"patrol")


func test_cold_rests_in_rich_rock() -> void:
	var s: Scenario = make({"seed": 26, "fixture": T.block()})
	var t: Tapper = T.tapper(s, Vector2i(20, 6))
	s.step(200)
	assert_true(t.heat.is_cold())
	assert_true(t.is_rich(s.run, t.tile(s.run)), "a cold map: it rests in rich rock")
	assert_gt(t.dwell_until, s.run.tick, "dwelling")
	assert_lte(t.dwell_until - s.run.tick, 90 * 20)


func test_relax_into_rich_rock() -> void:
	var s: Scenario = make({"seed": 27, "fixture": T.block()})
	var t: Tapper = T.tapper(s, Vector2i(20, 5))
	s.run.creatures.gate.relax_active = func() -> bool: return true
	s.run.noise.emit(NoiseTypes.Type.HAMMER, Vector2i(5, 4), {"level_np": 30.0})
	s.step(200)
	assert_true(t.is_rich(s.run, t.tile(s.run)), "a relax: into rich rock")


func test_start_in_rich_rock_by_ring() -> void:
	var s: Scenario = make({"seed": 28, "fixture": T.block()})
	var at: Variant = Tapper.start_tile(s.run, Vector2(0, 0))
	assert_true(at != null)
	var tile: Vector2i = at
	assert_true(s.run.mine.native.thickness(tile) >= 4, "rich rock")
	assert_eq(WorldCoords.ring_of_tile(tile), 0)
	assert_true(Tapper.start_tile(s.run) == null, "this fixture lies in ring 0: no ring 1-2 start")
	Tuning.set_dev_override("depth.ring_start_tiles", [5, 15, 1000, 1001])
	var r12: Variant = Tapper.start_tile(s.run)
	Tuning.clear_dev_overrides()
	assert_true(r12 != null)
	var r12_tile: Vector2i = r12
	Tuning.set_dev_override("depth.ring_start_tiles", [5, 15, 1000, 1001])
	var ring: int = WorldCoords.ring_of_tile(r12_tile)
	Tuning.clear_dev_overrides()
	assert_between(ring, 1, 2, "rings 1-2")
