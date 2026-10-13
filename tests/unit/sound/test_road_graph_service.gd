extends GutTest
## SND-01 through GDScript: the block format, validation, the service on GEN-01's test map.

var mine: Mine
var service: RoadGraphService


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	mine = Mine.new()
	assert_eq(mine.load_fixed_map("test"), 2)
	service = RoadGraphService.new(mine, 77)


func test_block_round_trips_through_json_and_bytes() -> void:
	var data: LbCellData = CellFile.load_file("res://data/maps/test/cell_0_0.json")
	var block: Dictionary = RoadGraphBlock.decode(data.get_road_graph())
	assert_eq(Variants.array(block["zones"]).size(), 4)
	assert_eq(Variants.array(block["portals"]).size(), 4)
	assert_eq(RoadGraphBlock.encode(block), data.get_road_graph())
	assert_eq(RoadGraphBlock.encode({}), PackedByteArray())


func test_test_map_stitches_and_validates() -> void:
	assert_eq(service.failed_cells, [] as Array[Vector2i])
	assert_true(service.graph.is_stitched(Vector2i(0, 0)))
	assert_true(service.graph.is_stitched(Vector2i(1, 0)))
	assert_eq(service.graph.validate(Vector2i(0, 0)), PackedStringArray())


func test_door_costs_and_the_detour() -> void:
	service.set_player_listener(1, Vector2i(11, 1))
	var shut: Array = service.propagate(1, [Vector2i(9, 1)] as Array[Vector2i], 14.0)
	assert_eq(shut.size(), 1)
	var d: Dictionary = Variants.dict(shut[0])
	assert_almost_eq(Variants.number(d["remaining_np"]), 2.0, 0.0001, "through the shut air door at -12")
	assert_eq(int(Variants.number(d["closed_portals"])), 1)
	var voice: Array = service.propagate(2, [Vector2i(9, 1)] as Array[Vector2i], 40.0, RoadGraphService.MODE_VOICE)
	assert_eq(voice.size(), 1, "voice goes round by the detour")
	var v: Dictionary = Variants.dict(voice[0])
	assert_eq(int(Variants.number(v["closed_portals"])), 0)
	assert_gt(Variants.number(v["path_tiles"]), 20.0)
	assert_eq(int(Variants.number(v["via"])), 5, "it enters the east corridor by the opening at (18, 5)")


func test_door_flip_reroutes_in_the_same_call() -> void:
	service.set_player_listener(1, Vector2i(11, 1))
	var before: int = service.graph.epoch()
	mine.native.set_barrier(Vector2i(0, 0), 1, true)
	assert_gt(service.graph.epoch(), before, "the tiles_changed signal rebuilt the cell")
	var open: Dictionary = Variants.dict(service.propagate(3, [Vector2i(9, 1)] as Array[Vector2i], 14.0)[0])
	assert_almost_eq(Variants.number(open["remaining_np"]), 14.0, 0.0001, "an open door is a free portal: no np lost")


func test_edge_link_into_the_next_cell_and_unload() -> void:
	service.set_player_listener(1, Vector2i(25, 1))
	var across: Array = service.propagate(4, [Vector2i(15, 1)] as Array[Vector2i], 20.0)
	assert_eq(across.size(), 1)
	assert_almost_eq(Variants.number(Variants.dict(across[0])["path_tiles"]), 10.0, 0.0001)
	mine.queue_unload(Vector2i(1, 0))
	mine.apply_pending()
	assert_false(service.graph.is_stitched(Vector2i(1, 0)))
	assert_eq(service.propagate(5, [Vector2i(15, 1)] as Array[Vector2i], 20.0).size(), 0)


func test_rock_line_and_nearest_open_tile() -> void:
	var line: Dictionary = service.graph.rock_line(Vector2i(2, 7), Vector2i(2, 4))
	assert_true(Variants.flag(line["has_face"]))
	var brick: Dictionary = service.graph.rock_line(Vector2i(10, 9), Vector2i(10, 11))
	assert_false(Variants.flag(brick["brick"]), "the shaft tile (10, 10) is floor")
	var through: Dictionary = service.graph.rock_line(Vector2i(5, 9), Vector2i(5, 11))
	assert_true(Variants.flag(through["brick"]))
	var near: Dictionary = service.graph.nearest_open_tile(Vector2i(2, 7), 3)
	assert_true(Variants.flag(near["found"]))
	var tile: Vector2i = near["tile"]
	assert_eq(tile, Vector2i(2, 5))


func test_deliver_is_pure() -> void:
	service.set_player_listener(1, Vector2i(11, 1))
	service.propagate(6, [Vector2i(9, 1)] as Array[Vector2i], 14.0)
	var epoch: int = service.graph.epoch()
	var d: Dictionary = service.graph.deliver(Vector2i(3, 1), 20.0, Vector2i(8, 1), RoadGraphService.MODE_AIR, 0.0, 1.0, 9)
	assert_almost_eq(Variants.number(d["path_tiles"]), 5.0, 0.0001)
	assert_eq(service.graph.epoch(), epoch)
