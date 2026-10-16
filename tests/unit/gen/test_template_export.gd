extends GutTest
## GEN-04: a template scene to its export. The fixture scene gives the expected JSON, sorted the
## same whatever its child order; the export loads back through GEN-01's loader and round-trips
## byte for byte, and packs the same; problems name the template, the rule and the tile; the
## exporter writes a set and its check fails on any drift; the dock validates the open scene; and a
## collapse's fallen zones swap into the Road Graph.

const EXPECTED: String = "res://tests/fixtures/templates/expected"
const SCRATCH: String = "user://test_template_export"


## A Seam cell (the native tests' base fixture): a 3-wide road west to east, a 1-wide road north
## with a collapse, a spur to a dead end, and a 6x6 chamber off the road.
static func spec() -> Dictionary:
	return {
		"id": "fixture_bend", "kind": "biome_cell", "biome": "seam", "footprint": [1, 1], "weight": 1.5, "author_version": 2,
		"rows": [
			"##########.#########", "##########.#########", "##########.#########", "##########.#########",
			"##########.#########", "##########.#########", "##########.#########", "##########.#########",
			"##########.#########", "....................", "====================", "....................",
			"##########.####.####", "#######......##.####", "#######......##.####", "#######......##.####",
			"#######......#######", "#######......#######", "#######......#######", "####################",
		],
		"anchors": [
			["chamber", 7, 13, 6, 6, ["high", "coat_heaps"], ""],
			["timber_hook", 2, 10, 1, 1, [], ""], ["timber_hook", 7, 10, 1, 1, [], ""],
			["timber_hook", 12, 10, 1, 1, [], ""], ["timber_hook", 17, 10, 1, 1, [], ""],
			["timber_hook", 10, 4, 1, 1, [], ""], ["timber_hook", 15, 13, 1, 1, [], ""],
			["timber_hook", 8, 14, 1, 1, [], ""],
			["landmark", 5, 9, 1, 1, [], "broken_tub"],
			["rubble_heap", 14, 11, 1, 1, [], ""],
			["rich_rock", 2, 1, 4, 4, [], ""],
			["wall_fixture", 9, 12, 1, 1, [], ""],
			["remains", 15, 15, 1, 1, [], ""],
			["door_site", 10, 12, 1, 1, [], ""],
			["gas_dead_end", 15, 12, 1, 4, [], ""],
		],
		"stubs": [
			{"cell": [0, 0], "edge": "west", "offset": 10, "max_width": 3, "depth": 2, "door": false},
			{"cell": [0, 0], "edge": "east", "offset": 10, "max_width": 3, "depth": 2, "door": false},
			{"cell": [0, 0], "edge": "north", "offset": 10, "max_width": 1, "depth": 0, "door": false},
		],
		"collapses": [{"id": 1, "tiles": [[10, 5, "#"]]}],
		"rib": [[6, 13, 200], [9, 8, 50]],
	}


static func _built(s: Dictionary) -> Dictionary:
	var src: TemplateSource = TemplateScaffold.from_spec(s)
	var built: Dictionary = TemplateBuild.build(src, _params())
	src.free()
	return built


static func _params() -> Dictionary:
	var tuning: TuningSet = TuningSet.new()
	tuning.load_directory(TuningSet.DATA_DIR)
	return TemplateBuild.rules(tuning)


func after_each() -> void:
	_remove_tree(ProjectSettings.globalize_path(SCRATCH))


func test_a_fixture_scene_exports_the_expected_json() -> void:
	var built: Dictionary = _built(spec())
	assert_eq(Variants.array(built["errors"]).size(), 0, str(built["errors"]))
	var files: Dictionary = TemplateBuild.files(Variants.dict(built["template"]))
	assert_eq(files.keys().size(), 2)
	for rel: Variant in files.keys():
		var expected: String = FileAccess.get_file_as_string(EXPECTED.path_join(str(rel)))
		assert_ne(expected, "", "expected fixture %s exists" % rel)
		assert_eq(str(files[rel]), expected, "export %s" % rel)
	assert_eq(TemplateBuild.validate(Variants.dict(built["template"]), _params()).size(), 0, "the fixture is valid")


func test_the_scene_order_never_changes_the_bytes() -> void:
	var shuffled: Dictionary = spec()
	var anchors: Array = Variants.array(shuffled["anchors"]).duplicate()
	anchors.reverse()
	shuffled["anchors"] = anchors
	var stubs: Array = Variants.array(shuffled["stubs"]).duplicate()
	stubs.reverse()
	shuffled["stubs"] = stubs
	var rib: Array = Variants.array(shuffled["rib"]).duplicate()
	rib.reverse()
	shuffled["rib"] = rib
	var a: Dictionary = TemplateBuild.files(Variants.dict(_built(spec())["template"]))
	var b: Dictionary = TemplateBuild.files(Variants.dict(_built(shuffled)["template"]))
	assert_eq(a, b)


func test_the_export_loads_back_and_round_trips_byte_for_byte() -> void:
	var template: Dictionary = Variants.dict(_built(spec())["template"])
	var files: Dictionary = TemplateBuild.files(template)
	for rel: Variant in files.keys():
		_write(SCRATCH.path_join(str(rel)), str(files[rel]))
	var loaded: Dictionary = TemplateBuild.load_export(SCRATCH.path_join("fixture_bend"))
	assert_false(loaded.is_empty())
	assert_eq(TemplateBuild.files(loaded), files, "loaded through GEN-01's CellFile, it writes the same bytes")
	var pack: PackedByteArray = LbTemplates.encode_pack("0123456789abcdef", [template])
	assert_eq(LbTemplates.encode_pack("0123456789abcdef", [loaded]), pack, "and packs the same")
	var decoded: Dictionary = LbTemplates.decode_pack(pack)
	assert_eq(str(decoded["set_version"]), "0123456789abcdef")
	assert_eq(LbTemplates.encode_pack("0123456789abcdef", Variants.array(decoded["templates"])), pack, "the pack round-trips")
	assert_eq(LbTemplates.decode_pack(pack.slice(0, pack.size() - 1)), {}, "a cut pack is refused")


func test_problems_name_the_template_the_rule_and_the_tile() -> void:
	var s: Dictionary = spec()
	var anchors: Array = []
	for a: Variant in Variants.array(s["anchors"]):
		var row: Array = Variants.array(a)
		if not (str(row[0]) == "timber_hook" and int(Variants.number(row[1])) == 10 and int(Variants.number(row[2])) == 4):
			anchors.append(row)
	s["anchors"] = anchors
	var problems: Array[String] = TemplateBuild.validate(Variants.dict(_built(s)["template"]), _params())
	assert_eq(problems.size(), 1, str(problems))
	if problems.size() == 1:
		assert_eq(problems[0], "template fixture_bend: timber_hooks: cell (0, 0) tile (10, 0): road tile more than 4 tiles by path from a timber hook")


func test_a_scene_that_cannot_be_a_template_says_why() -> void:
	var s: Dictionary = spec()
	s["footprint"] = [2, 1]
	s["anchors"] = [["rich_rock", 18, 2, 4, 2, [], ""]]
	var errors: Array = Variants.array(_built(s)["errors"])
	assert_eq(errors.size(), 1)
	assert_string_contains(str(errors[0]), "anchor rich_rock")
	assert_string_contains(str(errors[0]), "is not inside one cell of the footprint")
	var three: Dictionary = spec()
	three["footprint"] = [3, 1]
	assert_string_contains(str(Variants.array(_built(three)["errors"])[0]), "is not 1x1, 1x2, 2x1 or 2x2")


func test_the_exporter_writes_a_set_and_its_check_catches_drift() -> void:
	var root: String = SCRATCH.path_join("set")
	var src: TemplateSource = TemplateScaffold.from_spec(spec())
	var scene_path: String = root.path_join("src/biome_cell/seam/fixture_bend.tscn")
	assert_eq(TemplateScaffold.save(src, scene_path), OK)
	src.free()
	var wrote: Dictionary = TemplateExporter.run(false, root)
	assert_true(Variants.flag(wrote["ok"]), str(wrote["messages"]))
	var version: String = str(wrote["set_version"])
	assert_eq(version.length(), 16)
	assert_true(FileAccess.file_exists(root.path_join("packs/%s.lbtp" % version)))
	assert_true(FileAccess.file_exists(root.path_join("export/fixture_bend/cell_0_0.json")))
	assert_string_contains(FileAccess.get_file_as_string(root.path_join("set.json")), version)
	assert_true(Variants.flag(TemplateExporter.run(true, root)["ok"]), "the committed set checks clean")

	var pack_path: String = root.path_join("packs/%s.lbtp" % version)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(pack_path)
	bytes[bytes.size() - 1] ^= 1
	_write_bytes(pack_path, bytes)
	var tampered: Dictionary = TemplateExporter.run(true, root)
	assert_false(Variants.flag(tampered["ok"]))
	assert_string_contains(str(tampered["messages"]), "a changed pack needs a new set_version")
	assert_true(Variants.flag(TemplateExporter.run(false, root)["ok"]))

	var heavier: Dictionary = spec()
	heavier["weight"] = 2.0
	var changed: TemplateSource = TemplateScaffold.from_spec(heavier)
	TemplateScaffold.save(changed, scene_path)
	changed.free()
	var drift: Dictionary = TemplateExporter.run(true, root)
	assert_false(Variants.flag(drift["ok"]), "a changed source fails the check until re-exported")
	assert_string_contains(str(drift["messages"]), "export/fixture_bend/template.json is out of date")
	assert_ne(str(drift["set_version"]), version, "with a new set_version")

	var broken: Dictionary = spec()
	broken["anchors"] = []
	var bad: TemplateSource = TemplateScaffold.from_spec(broken)
	TemplateScaffold.save(bad, scene_path)
	bad.free()
	var refused: Dictionary = TemplateExporter.run(false, root)
	assert_false(Variants.flag(refused["ok"]))
	assert_string_contains(str(refused["messages"]), "template fixture_bend: landmark_rubble")
	assert_string_contains(FileAccess.get_file_as_string(root.path_join("set.json")), version, "an invalid template writes nothing")

	var misplaced: TemplateSource = TemplateScaffold.from_spec(spec())
	TemplateScaffold.save(misplaced, root.path_join("src/biome_cell/seam/fixture_bend.tscn"))
	TemplateScaffold.save(misplaced, root.path_join("src/poi/seam/fixture_bend.tscn"))
	misplaced.free()
	var twice: Dictionary = TemplateExporter.run(true, root)
	assert_string_contains(str(twice["messages"]), "belongs at")
	assert_string_contains(str(twice["messages"]), "template id fixture_bend is used twice")


func test_the_dock_validates_the_open_scene() -> void:
	var panel: TemplatesPanel = TemplatesPanel.new()
	assert_string_contains(panel.validate_open(), "Open a template scene")
	var src: TemplateSource = TemplateScaffold.from_spec(spec())
	panel.edited_root = func() -> Node: return src
	assert_eq(panel.validate_open(), "Template fixture_bend is valid.")
	var hookless: Dictionary = spec()
	hookless["anchors"] = Variants.array(hookless["anchors"]).filter(func(a: Variant) -> bool: return str(Variants.array(a)[0]) != "timber_hook")
	var bare: TemplateSource = TemplateScaffold.from_spec(hookless)
	panel.edited_root = func() -> Node: return bare
	assert_string_contains(panel.validate_open(), "template fixture_bend: timber_hooks: cell (0, 0) tile (")
	src.free()
	bare.free()
	panel.free()


func test_a_new_template_is_all_rock_with_its_layers() -> void:
	var src: TemplateSource = TemplateScaffold.empty("seam_new_01", "biome_cell", "seam", Vector2i(2, 1))
	var path: String = SCRATCH.path_join("new.tscn")
	assert_eq(TemplateScaffold.save(src, path), OK)
	src.free()
	var scene: PackedScene = load(path) as PackedScene
	var again: TemplateSource = scene.instantiate() as TemplateSource
	assert_not_null(again)
	assert_eq(again.footprint, Vector2i(2, 1))
	var geometry: TileMapLayer = again.get_node("Geometry") as TileMapLayer
	assert_eq(geometry.get_used_cells().size(), 800)
	assert_eq(TemplateBuild.char_at(geometry, Vector2i(39, 19), &"char"), "#")
	assert_not_null(again.get_node_or_null("Rib"))
	again.free()


func test_a_collapse_swaps_its_fallen_zones_into_the_road_graph() -> void:
	var template: Dictionary = Variants.dict(_built(spec())["template"])
	var cells: Array = Variants.array(template["cells"])
	var cell: LbCellData = cells[0]
	var collapse: Dictionary = Variants.dict(cell.get_collapses()[0])
	assert_eq(Variants.array(collapse["zones"]).size(), 5, "the north road beyond the fall becomes its own zone")
	var mine: LbMine = LbMine.new()
	var materials: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string("res://data/world/materials.json")))
	mine.set_material_table(Variants.dict(materials.get("materials", materials)))
	assert_true(mine.commit(cell))
	var graph: LbRoadGraph = LbRoadGraph.new()
	graph.attach(mine)
	assert_true(graph.stitch(Vector2i.ZERO))
	var north: Vector2i = Vector2i(10, 1)
	var road: Vector2i = Vector2i(10, 10)
	assert_gt(graph.path_cost(north, road, LbRoadGraph.MODE_AIR, 1000.0), 0.0, "standing: the road joins")
	var standing: int = graph.tables_digest()
	assert_true(mine.set_collapse(Vector2i.ZERO, 1, true))
	graph.on_tiles_changed(Vector2i.ZERO, Rect2i(10, 5, 1, 1), "collapse_fallen")
	assert_true(graph.is_stitched(Vector2i.ZERO), "the fallen set is a valid block")
	assert_eq(mine.zone_at(north), 3)
	assert_eq(mine.zone_at(road), 2)
	assert_eq(graph.path_cost(north, road, LbRoadGraph.MODE_AIR, 1000.0), -1.0, "fallen: no road between them")
	assert_true(mine.set_collapse(Vector2i.ZERO, 1, false))
	graph.on_tiles_changed(Vector2i.ZERO, Rect2i(10, 5, 1, 1), "collapse_standing")
	assert_eq(graph.tables_digest(), standing, "standing again, the tables are as they were")
	assert_eq(mine.zone_at(north), 2)


static func _write(path: String, text: String) -> void:
	_write_bytes(path, text.to_utf8_buffer())


static func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


static func _remove_tree(dir: String) -> void:
	var d: DirAccess = DirAccess.open(dir)
	if d == null:
		return
	for f: String in d.get_files():
		DirAccess.remove_absolute(dir.path_join(f))
	for sub: String in d.get_directories():
		_remove_tree(dir.path_join(sub))
	DirAccess.remove_absolute(dir)
