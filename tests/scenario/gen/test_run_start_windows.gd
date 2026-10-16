extends "res://tests/scenario/kit/scenario_test.gd"
## GEN-11: run start generates the windows round base camp and round each creature's start before
## the first tick (GDD §15.9: creatures live only in generated cells), and a creature holds a window
## wherever it goes, so it never stands in, or paths into, an unloaded cell. CRT-01 picks the starts
## and GEN-10 the homes; here a stand-in creature (a bare Moth entity) starts in a far cell.

const Specs = preload("res://tests/unit/gen/template_specs.gd")

const START: Vector2i = Vector2i(12, 3)


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_creature_start_and_its_window_are_there_before_the_first_tick() -> void:
	var s: Scenario = make({"seed": 4111, "generated": {"pack": Specs.road_pack(), "centres": [START]}})
	assert_eq(s.run.tick, 0, "nothing has ticked")
	var radius: int = Tuning.i(&"mine.generation_radius_cells")
	assert_eq(_missing(s, START, radius), [] as Array[Vector2i], "the creature's window is generated")
	assert_eq(_missing(s, Vector2i.ZERO, radius), [] as Array[Vector2i], "and base camp's")
	assert_eq(s.generation.failures, 0)


func test_a_creature_holds_a_window_wherever_it_goes() -> void:
	var s: Scenario = make({"seed": 4111, "generated": {"pack": Specs.road_pack(), "centres": [START]}})
	var radius: int = Tuning.i(&"mine.generation_radius_cells")
	var moth: SimEntity = s.run.registry.create(WorldIds.EntityKind.MOTH, _centre(START), SimEntity.FLAG_MOTIONLESS)
	# It walks south a cell every few ticks, far from base camp and any miner.
	var cell: Vector2i = START
	var holes: int = 0
	for step: int in 12:
		cell += Vector2i(0, 1)
		s.run.registry.move(moth.id, _centre(cell))
		s.step(3)
		var at: Vector2i = WorldCoords.cell_of(WorldCoords.tile_at(moth.position))
		assert_true(s.mine.native.is_loaded(at), "the creature's cell is loaded (step %d)" % step)
		holes += _missing(s, at, radius).size()
	assert_eq(holes, 0, "every cell within %d of the creature was loaded on every step" % radius)
	# Its start, now far behind it, is dropped: more than 6 from every holder.
	s.step(2)
	assert_false(s.mine.native.is_loaded(START), "the start cell left memory once everyone was beyond 6 cells")
	assert_true(s.mine.native.is_loaded(Vector2i.ZERO), "base camp never does")


func _missing(s: Scenario, centre: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y: int in range(centre.y - radius, centre.y + radius + 1):
		for x: int in range(centre.x - radius, centre.x + radius + 1):
			if not s.mine.native.is_loaded(Vector2i(x, y)):
				out.append(Vector2i(x, y))
	return out


static func _centre(cell: Vector2i) -> Vector2:
	return Vector2(cell * WorldIds.CELL_TILES) + Vector2(10.5, 10.5)
