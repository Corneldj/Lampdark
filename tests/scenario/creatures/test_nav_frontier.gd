extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-02: no path enters ungenerated cells; a creature walking into ungenerated ground stops at
## the frontier and resumes within 2 ticks of the cell arriving; no cell within 4 cells of a
## creature is evicted.


func before_all() -> void:
	assert_true(Tuning.load_server())


func _road(width: int) -> PackedStringArray:
	return PackedStringArray(["#".repeat(width), "#".repeat(width), "#" + ".".repeat(width - 2) + "#", "#".repeat(width), "#".repeat(width)])


func test_frontier() -> void:
	var fixture: FixtureMap = FixtureMap.from_ascii(_road(40))
	var s: Scenario = make({"seed": 31, "fixture": fixture})
	s.run.mine.native.unload(Vector2i(1, 0))
	assert_ne(s.place_stand_in(WorldIds.EntityKind.MOTH, Vector2i(2, 2)), 0)
	var moth: KitCreature = s.run.creatures.creature_of_kind(WorldIds.EntityKind.MOTH)
	moth.follower = NavFollower.new()
	moth.max_speed = 5.0
	moth.speed = 5.0
	moth.follower.go(s.run, s.run.creatures.nav, moth, Vector2i(35, 2), NavModes.Mode.WALKER)
	assert_eq(moth.follower.status, NavFollower.Status.FRONTIER, "the goal lies in ungenerated ground")
	s.step(20)
	assert_eq(moth.follower.status, NavFollower.Status.FRONTIER)
	assert_lt(moth.position(s.run).x, 20.0, "it never enters the ungenerated cell")
	var at_frontier: Vector2 = moth.position(s.run)
	var cell: Dictionary = fixture.cells[1]
	s.run.mine.queue_commit(CellFile.from_dict(cell, "fixture"))
	var arrived: int = s.run.tick
	var moved: int = -1
	for i: int in 4:
		s.step(1)
		if moved < 0 and moth.position(s.run) != at_frontier:
			moved = s.run.tick
	gut.p("cell committed at tick %d, moving again by tick %d" % [arrived, moved])
	assert_between(moved - arrived, 1, 2, "resumes within 2 ticks of the cell arriving")


func test_cells_near_a_creature_stay() -> void:
	var s: Scenario = make({"seed": 32, "fixture": FixtureMap.from_ascii(_road(120))})
	assert_ne(s.place_stand_in(WorldIds.EntityKind.MOTH, Vector2i(2, 2)), 0)
	for c: int in [1, 4, 5]:
		s.run.mine.queue_unload(Vector2i(c, 0))
	s.step(1)
	assert_true(s.run.mine.native.is_loaded(Vector2i(1, 0)), "within 4 cells: kept")
	assert_true(s.run.mine.native.is_loaded(Vector2i(4, 0)), "4 cells off: kept")
	assert_false(s.run.mine.native.is_loaded(Vector2i(5, 0)), "5 cells off: evicted")
	assert_eq(s.run.mine.refused_unloads, 2)
