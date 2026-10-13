extends GutTest
## Base camp's emergency lamps, and a gate's spill opened and shut (VIS-02).


func before_all() -> void:
	assert_true(Tuning.load_server())


func _camp() -> LbCellData:
	var rows: Array = []
	for y: int in 20:
		var row: String = ""
		for x: int in 20:
			var ch: String = "B"
			if y >= 2 and y <= 9 and x >= 2 and x <= 9:
				ch = "."
			elif y == 5 and x == 10:
				ch = "S"
			elif y == 5 and x > 10:
				ch = "."
			elif (y == 4 or y == 6) and x > 10:
				ch = "#"
			row += ch
		rows.append(row)
	var zones: Array = []
	for _y: int in 20:
		var zr: Array = []
		zr.resize(20)
		zr.fill(0)
		zones.append(zr)
	return CellFile.from_dict({"format": 1, "cell": [0, 0], "tiles": rows, "zones": zones,
		"barriers": [{"id": 1, "portal": 1, "tiles": [110], "open": false}]}, "camp")


func test_emergency_lamps_and_gate_spill() -> void:
	var mine: Mine = Mine.new()
	mine.queue_commit(_camp())
	var run: RunState = RunState.create(1, ServerConfig.Mode.FRIENDS, false)
	run.add_system(MineCommitSystem.new(mine))
	var light: LightSystem = LightSystem.new(mine)
	light.register_into(run)
	run.run_tick()
	var floor_tiles: Array = []
	for y: int in range(2, 10):
		for x: int in range(2, 10):
			floor_tiles.append(Vector2i(x, y))
	light.grid.add_area("emergency", LbLightGrid.COLOUR_WHITE, 0, Tuning.f(&"basecamp.emergency_light_level"), floor_tiles)
	light.grid.add_spill("gate_spill", LbLightGrid.COLOUR_WHITE, 0, [Vector2i(10, 5)], Vector2i(1, 0), 6.0, 0.6, 0.12)
	run.run_tick()
	for tile: Variant in floor_tiles:
		var t: Vector2i = tile
		assert_eq(light.grid.value(t), 600, "base camp floor %s" % t)
	assert_eq(light.grid.value(Vector2i(11, 5)), 0, "a shut gate spills nothing")
	mine.native.set_barrier(Vector2i(0, 0), 1, true)
	run.run_tick()
	assert_eq(light.grid.value(Vector2i(11, 5)), 560)
	assert_eq(light.grid.value(Vector2i(14, 5)), 320, "0.30 or more to 3.75 tiles")
	assert_eq(light.grid.value(Vector2i(15, 5)), 240)
	assert_eq(light.grid.value(Vector2i(17, 5)), 0)
	mine.native.set_barrier(Vector2i(0, 0), 1, false)
	run.run_tick()
	assert_eq(light.grid.value(Vector2i(11, 5)), 0, "shut again")
	assert_lt(light.grid.last_update_usec(), 2000)
