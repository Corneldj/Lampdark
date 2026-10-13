extends GutTest
## A 14 np hammer strike inside base camp reaches the road beyond a shut gate at 2 np, and never
## reaches a Tapper listener there (SND-01, Gameplay §3.2).


func before_all() -> void:
	assert_true(Tuning.load_server())


func _camp() -> LbCellData:
	var rows: Array = []
	var zones: Array = []
	for y: int in 20:
		var row: String = ""
		var zone_row: Array = []
		for x: int in 20:
			var ch: String = "B"
			var zone: int = 0
			if y >= 2 and y <= 9 and x >= 2 and x <= 9:
				ch = "."
				zone = 1
			elif y == 5 and x == 10:
				ch = "S"
			elif y == 5 and x > 10:
				ch = "."
				zone = 2
			elif (y == 4 or y == 6) and x > 10:
				ch = "#"
			row += ch
			zone_row.append(zone)
		rows.append(row)
		zones.append(zone_row)
	return CellFile.from_dict({"format": 1, "cell": [0, 0], "tiles": rows, "zones": zones,
		"barriers": [{"id": 1, "portal": 1, "tiles": [110], "open": false}],
		"road_graph": {"zones": [{"id": 1, "kind": "base_camp"}, {"id": 2, "kind": "road"}],
			"portals": [{"id": 1, "kind": "gate", "a": 1, "b": 2, "barrier": 1, "tiles": [110]}]}}, "camp")


func test_hammer_strike_past_a_shut_gate() -> void:
	var mine: Mine = Mine.new()
	mine.native.commit(_camp())
	var service: RoadGraphService = RoadGraphService.new(mine, 1)
	assert_eq(service.failed_cells, [] as Array[Vector2i])
	var hammer: float = Tuning.f(&"noise.hammer_np")
	assert_eq(hammer, 14.0)
	service.set_player_listener(1, Vector2i(11, 5))
	service.set_creature_listener(2, Vector2i(11, 5), 1.0)
	var heard: Array = service.propagate(1, [Vector2i(9, 5)] as Array[Vector2i], hammer)
	assert_eq(heard.size(), 1, "the player hears it; the Tapper (threshold 4) does not")
	var d: Dictionary = Variants.dict(heard[0])
	assert_eq(int(Variants.number(d["listener"])), 1)
	assert_almost_eq(Variants.number(d["remaining_np"]), 2.0, 0.0001)
	var deep: Array = service.propagate(2, [Vector2i(9, 5)] as Array[Vector2i], hammer)
	assert_eq(deep.size(), 1)
	service.remove_listener(1)
	service.set_creature_listener(2, Vector2i(11, 5), 1.6)
	assert_eq(service.propagate(3, [Vector2i(9, 5)] as Array[Vector2i], hammer).size(), 0, "not even in the Deep")
	mine.native.set_barrier(Vector2i(0, 0), 1, true)
	assert_eq(service.propagate(4, [Vector2i(9, 5)] as Array[Vector2i], hammer).size(), 1, "an open gate lets the Tapper hear")
