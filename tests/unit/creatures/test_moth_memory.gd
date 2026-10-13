extends GutTest
## CRT-04: the Moth remembers the last 2 + crew count lights, each for 60 s, merging any within
## 4 tiles.


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_capacity_by_crew() -> void:
	for crew: int in range(1, 6):
		var cap: int = CreatureTables.moth_memory_lights(crew)
		assert_eq(cap, 2 + crew)
		var mem: MothMemory = MothMemory.new()
		for i: int in cap + 3:
			mem.remember(Vector2(i * 10.0, 0.0), 1.0, i, cap)
		assert_eq(mem.lights.size(), cap, "crew %d: %d lights" % [crew, cap])
		assert_eq(mem.lights[0].tick, cap + 2, "the newest kept")
		assert_eq(mem.lights[mem.lights.size() - 1].tick, 3, "the oldest dropped first")


func test_sixty_seconds() -> void:
	var mem: MothMemory = MothMemory.new()
	mem.remember(Vector2(5, 5), 1.0, 0, 5)
	mem.prune(1199)
	assert_eq(mem.lights.size(), 1, "kept at 59.95 s")
	mem.prune(1200)
	assert_eq(mem.lights.size(), 0, "forgotten at 60 s")


func test_merge_within_four_tiles() -> void:
	var mem: MothMemory = MothMemory.new()
	mem.remember(Vector2(10, 10), 1.0, 0, 5)
	mem.remember(Vector2(13.9, 10), 2.0, 5, 5)
	assert_eq(mem.lights.size(), 1, "within 4 tiles: one light")
	assert_eq(mem.lights[0].tick, 5, "refreshed")
	assert_eq(mem.lights[0].centroid, Vector2(13.9, 10))
	mem.remember(Vector2(18.0, 10), 1.0, 6, 5)
	assert_eq(mem.lights.size(), 2, "4.1 tiles away: another")
	var order: Array[MothMemory.Light] = mem.nearest_first(Vector2(20, 10))
	assert_eq(order[0].centroid, Vector2(18.0, 10), "nearest first")
