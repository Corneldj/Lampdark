extends GutTest
## GEN-01 through GDScript: fixed files, the material table, fields, signals, the commit queue.

const DOOR_CELL: Vector2i = Vector2i(0, 0)
const GOLDEN_DIGESTS: Dictionary = {
	"cell_0_0.json": "042a69d40c0c3192",
	"cell_1_0.json": "c45e438a746bbfc3",
}

var loaded: Array[Vector2i] = []
var changes: Array[Array] = []


func before_all() -> void:
	assert_true(Tuning.load_server())


func _mine() -> Mine:
	var mine: Mine = Mine.new()
	loaded.clear()
	changes.clear()
	mine.native.cell_loaded.connect(func(cell: Vector2i) -> void: loaded.append(cell))
	mine.native.tiles_changed.connect(func(cell: Vector2i, rect: Rect2i, reason: String) -> void: changes.append([cell, rect, reason]))
	assert_eq(mine.load_fixed_map("test"), 2)
	return mine


func test_fixed_files_round_trip_byte_for_byte() -> void:
	for file: String in GOLDEN_DIGESTS.keys():
		var path: String = "res://data/maps/test/" + file
		var data: LbCellData = CellFile.load_file(path)
		assert_not_null(data, file)
		assert_eq(CellFile.serialize(data), FileAccess.get_file_as_string(path), "%s re-serialises byte for byte" % file)
		assert_eq(LbHash.to_hex(data.digest()), str(GOLDEN_DIGESTS[file]), "%s golden digest" % file)


func test_material_table_matches_world_ids_captions() -> void:
	var file: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(Mine.MATERIALS)))
	var table: Dictionary = Variants.dict(file["materials"])
	for name: Variant in table.keys():
		var id: int = int(Variants.number(WorldIds.TileMaterial.get(str(name), -1)))
		assert_ne(id, -1, "%s is an FND-07 material" % name)
		assert_eq(str(Variants.dict(table[name])["caption_key"]), str(WorldIds.MATERIAL_CAPTION_KEYS[id]), "%s caption" % name)


func test_load_and_query() -> void:
	var mine: Mine = _mine()
	assert_eq(loaded, [Vector2i(0, 0), Vector2i(1, 0)] as Array[Vector2i], "cell_loaded per cell")
	var native: LbMine = mine.native
	assert_eq(native.material_at(Vector2i(1, 7)), WorldIds.TileMaterial.COAL)
	assert_false(native.is_walkable(Vector2i(10, 1)), "the shut air door")
	assert_true(native.is_walkable(Vector2i(10, 12)), "the open gate is floor")
	assert_eq(native.state_at(Vector2i(3, 5)) & CellFile.STATE_RAIL, CellFile.STATE_RAIL)
	assert_eq(native.state_at(Vector2i(11, 5)) & CellFile.STATE_MUD, CellFile.STATE_MUD)
	assert_true(native.tapper_face_usable(Vector2i(1, 6)), "rock under the road")
	assert_false(native.tapper_face_usable(Vector2i(10, 10 - 1)), "floor is no face")
	assert_false(native.tapper_face_usable(Vector2i(9, 10)), "brick never")
	assert_eq(native.strike_milli(Vector2i(5, 1)), 500)
	assert_eq(native.thickness(Vector2i(2, 7)), 4, "the coal mass is 4 thick")
	var anchors: Array = native.anchors(DOOR_CELL)
	assert_eq(anchors.size(), 6)
	assert_eq(str(Variants.dict(anchors[4])["kind"]), "lamp_cabin")
	assert_eq(LbHash.to_hex(native.digest(Vector2i(1, 0))), "c45e438a746bbfc3")


func test_path_queries_through_bindings() -> void:
	var mine: Mine = _mine()
	assert_eq(mine.path_distance(Vector2i(1, 1), Vector2i(18, 1)).distance, 25.0, "the detour while the door is shut")
	assert_eq(mine.path_distance(Vector2i(1, 1), Vector2i(18, 1), -1.0, true).distance, 17.0, "doors-open")
	var into_next: Mine.PathAnswer = mine.path_distance(Vector2i(1, 1), Vector2i(30, 1))
	assert_eq(into_next.distance, 29.0 + 8.0, "across the cell border, round the door")
	var unloaded: Mine.PathAnswer = mine.path_distance(Vector2i(19, 1), Vector2i(45, 1))
	assert_eq(unloaded.distance, -1.0)
	assert_true(unloaded.touched_unloaded)
	var nearest: Dictionary = mine.native.nearest_open_tile(Vector2(10.5, 0.2), [], 3)
	assert_true(Variants.flag(nearest["found"]))
	var tile: Vector2i = nearest["tile"]
	assert_eq(tile, Vector2i(9, 1), "the door tile is shut, so the lowest index of the two neighbours wins")


func test_barrier_flip_signals_in_the_same_call() -> void:
	var mine: Mine = _mine()
	assert_true(mine.native.set_barrier(DOOR_CELL, 1, true))
	assert_eq(changes.size(), 1, "tiles_changed before anything else reads tiles")
	var rect: Rect2i = changes[0][1]
	var reason: String = changes[0][2]
	assert_eq(rect, Rect2i(10, 1, 1, 1))
	assert_eq(reason, "barrier_open")
	assert_true(mine.native.is_walkable(Vector2i(10, 1)))
	assert_true(mine.native.set_collapse(DOOR_CELL, 3, true))
	var second_reason: String = changes[1][2]
	assert_eq(second_reason, "collapse_fallen")
	assert_false(mine.native.is_walkable(Vector2i(9, 5)))


func test_worker_built_cell_commits_only_when_applied() -> void:
	var mine: Mine = Mine.new()
	var worker: Thread = Thread.new()
	worker.start(func() -> void:
		var data: LbCellData = CellFile.load_file("res://data/maps/test/cell_1_0.json")
		mine.queue_commit(data))
	worker.wait_to_finish()
	assert_eq(mine.pending_count(), 1)
	assert_false(mine.native.is_loaded(Vector2i(1, 0)), "nothing is visible before the tick applies it")
	mine.apply_pending()
	assert_true(mine.native.is_loaded(Vector2i(1, 0)))
	assert_true(mine.native.is_walkable(Vector2i(25, 1)))
	mine.queue_unload(Vector2i(1, 0))
	assert_true(mine.native.is_loaded(Vector2i(1, 0)))
	mine.apply_pending()
	assert_false(mine.native.is_loaded(Vector2i(1, 0)))
