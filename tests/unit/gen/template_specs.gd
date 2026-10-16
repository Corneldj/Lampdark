extends RefCounted
## Template fixtures for the generator's tests (GEN-04 to GEN-06): plain grid cells (3-wide roads on
## every stub line, a stub at all 12 positions) of any kind and biome, and packs built from them
## through the plugin's own build.


## A grid cell: roads on rows and columns 4-6, 9-11 and 14-16, hooks, a landmark and a heap.
static func grid_spec(id: String, kind: String, biome: String, weight: float) -> Dictionary:
	var rows: Array = []
	for y: int in 20:
		var road: bool = (y >= 4 and y <= 6) or (y >= 9 and y <= 11) or (y >= 14 and y <= 16)
		rows.append("...................." if road else "####...##...##...###")
	var anchors: Array = [["landmark", 2, 5, 1, 1, [], "chalk"], ["rubble_heap", 8, 5, 1, 1, [], ""]]
	var stubs: Array = []
	for a: int in [5, 10, 15]:
		for b: int in [5, 10, 15]:
			anchors.append(["timber_hook", a, b, 1, 1, [], ""])
		anchors.append(["timber_hook", 1, a, 1, 1, [], ""])
		anchors.append(["timber_hook", 18, a, 1, 1, [], ""])
		anchors.append(["timber_hook", a, 1, 1, 1, [], ""])
		anchors.append(["timber_hook", a, 18, 1, 1, [], ""])
		for edge: String in ["north", "east", "south", "west"]:
			stubs.append({"cell": [0, 0], "edge": edge, "offset": a, "max_width": 3, "depth": 0, "door": false})
	return {"id": id, "kind": kind, "biome": biome, "footprint": [1, 1], "weight": weight, "rows": rows, "anchors": anchors,
		"stubs": stubs}


## The validation rules from the data's tuning.
static func rules() -> Dictionary:
	var tuning: TuningSet = TuningSet.new()
	tuning.load_directory(TuningSet.DATA_DIR)
	return TemplateBuild.rules(tuning)


## A pack of `specs`, each built and validated as the exporter would; `problems` collects any.
static func pack(specs: Array, problems: Array[String] = []) -> PackedByteArray:
	var rules_now: Dictionary = rules()
	var templates: Array = []
	for raw: Variant in specs:
		var src: TemplateSource = TemplateScaffold.from_spec(Variants.dict(raw))
		var built: Dictionary = TemplateBuild.build(src, rules_now)
		src.free()
		var template: Dictionary = Variants.dict(built["template"])
		problems.append_array(Variants.array(built["errors"]))
		problems.append_array(TemplateBuild.validate(template, rules_now))
		templates.append(template)
	return LbTemplates.encode_pack("fixture", templates)


## Grid templates and a plain fallback for every biome in GEN-06's table.
static func every_biome_pack(problems: Array[String] = []) -> PackedByteArray:
	var specs: Array = []
	for biome: String in ["pit_bottom", "seam", "old_workings", "black_seam", "old_mens"]:
		specs.append(grid_spec("%s_grid" % biome, "biome_cell", biome, 1.0))
		specs.append(grid_spec("%s_plain" % biome, "fallback", biome, 1.0))
	return pack(specs, problems)
