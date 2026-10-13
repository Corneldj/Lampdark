extends GutTest
## Generated world constants match world_ids.json; entity IDs follow FND-07's rules.

const SOURCE: String = "res://shared/ids/world_ids.json"

var source: Dictionary


func before_all() -> void:
	source = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(SOURCE)))


func test_constants_match_json() -> void:
	var constants: Dictionary = Variants.dict(source.get("constants", {}))
	var script_constants: Dictionary = (WorldIds as Script).get_script_constant_map()
	for name: Variant in constants.keys():
		var generated: int = int(Variants.number(script_constants.get(str(name), -999)))
		assert_eq(generated, int(Variants.number(constants[name])), str(name))


func test_materials_and_captions_match_json() -> void:
	for raw: Variant in Variants.array(source.get("materials", [])):
		var entry: Dictionary = Variants.dict(raw)
		var id: int = int(Variants.number(entry["id"]))
		assert_eq(int(Variants.number(WorldIds.TileMaterial.get(str(entry["name"]), -1))), id, str(entry["name"]))
		assert_eq(str(WorldIds.MATERIAL_CAPTION_KEYS[id]), str(entry["caption_key"]))
	assert_eq(WorldIds.MATERIAL_CAPTION_KEYS[WorldIds.TileMaterial.ROCK], WorldIds.MATERIAL_CAPTION_KEYS[WorldIds.TileMaterial.COAL])


func test_entity_kinds_match_json() -> void:
	var kinds: Array = Variants.array(source.get("entity_kinds", []))
	assert_eq(WorldIds.EntityKind.size(), kinds.size() + 1, "NONE plus every kind")
	for raw: Variant in kinds:
		var entry: Dictionary = Variants.dict(raw)
		assert_eq(int(Variants.number(WorldIds.EntityKind.get(str(entry["name"]), -1))), int(Variants.number(entry["id"])))


func test_cell_size_agrees_with_tuning() -> void:
	var tuning: TuningSet = TuningSet.new()
	assert_eq(tuning.load_directory(TuningSet.DATA_DIR), [] as Array[String])
	assert_eq(tuning.i(&"mine.cell_tiles"), WorldIds.CELL_TILES)


func test_entity_ids() -> void:
	var ids: LbEntityIds = LbEntityIds.new()
	var last: int = 0
	for _i: int in 100:
		var id: int = ids.allocate()
		assert_gt(id, last)
		last = id
	assert_eq(ids.get_next(), 101)
	var resumed: LbEntityIds = LbEntityIds.new()
	resumed.restore(ids.get_next())
	assert_eq(resumed.allocate(), 101, "a restored counter continues, never reusing an ID")
	var from_zero: LbEntityIds = LbEntityIds.new()
	from_zero.restore(0)
	assert_eq(from_zero.allocate(), 1, "0 is never issued")
