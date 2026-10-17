extends RefCounted
## Template fixtures for the generator's tests (GEN-04 to GEN-06): plain grid cells (3-wide roads on
## every stub line, a stub at all 12 positions) of any kind and biome, and packs built from them
## through the plugin's own build.


## The widest socket each biome allows (GEN-06's table): its grid's corridors and stubs.
const BIOME_WIDTH: Dictionary = {"pit_bottom": 3, "seam": 3, "old_workings": 2, "black_seam": 3, "old_mens": 1}


## A grid cell: corridors `width` wide on every stub line (by GEN-05's opening rule, the biome's
## widest by default), hooks, a landmark and a heap.
static func grid_spec(id: String, kind: String, biome: String, weight: float, width: int = 0) -> Dictionary:
	var w: int = width if width > 0 else int(Variants.number(BIOME_WIDTH.get(biome, 3)))
	var on_line: Callable = func(i: int) -> bool:
		for o: int in [5, 10, 15]:
			if i >= o - w / 2 and i < o - w / 2 + w:
				return true
		return false
	var rows: Array = []
	for y: int in 20:
		var row: String = ""
		for x: int in 20:
			row += "." if on_line.call(x) or on_line.call(y) else "#"
		rows.append(row)
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
			stubs.append({"cell": [0, 0], "edge": edge, "offset": a, "max_width": w, "depth": 0, "door": false})
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


## The shipped set's pack (data/templates/set.json's current set: GEN-16's v1 and on).
static func shipped_pack() -> PackedByteArray:
	var current: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string("res://data/templates/set.json")))
	return FileAccess.get_file_as_bytes("res://data/templates/packs/%s.lbtp" % str(current["set_version"]))


## Grid templates and a plain fallback for every biome in GEN-06's table.
static func every_biome_pack(problems: Array[String] = []) -> PackedByteArray:
	var specs: Array = []
	for biome: String in ["pit_bottom", "seam", "old_workings", "black_seam", "old_mens"]:
		specs.append(grid_spec("%s_grid" % biome, "biome_cell", biome, 1.0))
		specs.append(grid_spec("%s_plain" % biome, "fallback", biome, 1.0))
	return pack(specs, problems)


## A main-road template drawn east to west (GEN-07): a 3-wide railed road on rows 9-11 with
## side passages on every stub line; a chicane bend at 5, 10 or 15; a crossing; or a straight road
## with an old fall at its middle and exits north at 5 and south at 15.
static func main_road_spec(id: String, shape: String, old_fall: bool, weight: float = 1.0) -> Dictionary:
	var rows: Array[PackedStringArray] = []
	for y: int in 20:
		var row: PackedStringArray = PackedStringArray()
		row.resize(20)
		row.fill("#")
		rows.append(row)
	var put: Callable = func(x: int, y: int, ch: String) -> void:
		var r: PackedStringArray = rows[y]
		r[x] = ch
		rows[y] = r
	for x: int in 20:
		put.call(x, 9, ".")
		put.call(x, 10, "=")
		put.call(x, 11, ".")
	var stubs: Array = [{"cell": [0, 0], "edge": "west", "offset": 10, "max_width": 3, "depth": 0, "door": false},
		{"cell": [0, 0], "edge": "east", "offset": 10, "max_width": 3, "depth": 0, "door": false}]
	if shape == "crossing":
		for y: int in 20:
			for x: int in range(9, 12):
				put.call(x, y, "=" if x == 10 or y == 10 else ".")
		for edge: String in ["north", "south"]:
			stubs.append({"cell": [0, 0], "edge": edge, "offset": 10, "max_width": 3, "depth": 0, "door": false})
	elif old_fall:
		for y: int in range(0, 9):
			for x: int in range(4, 7):
				put.call(x, y, ".")
		for y: int in range(12, 20):
			for x: int in range(14, 17):
				put.call(x, y, ".")
		for y: int in range(9, 12):
			for x: int in range(9, 12):
				put.call(x, y, "#")
		stubs.append({"cell": [0, 0], "edge": "north", "offset": 5, "max_width": 3, "depth": 0, "door": false})
		stubs.append({"cell": [0, 0], "edge": "south", "offset": 15, "max_width": 3, "depth": 0, "door": false})
	else:
		for c: int in [5, 10, 15]:
			for y: int in 20:
				if y < 9 or y > 11:
					for x: int in range(c - 1, c + 2):
						put.call(x, y, ".")
			for edge: String in ["north", "south"]:
				stubs.append({"cell": [0, 0], "edge": edge, "offset": c, "max_width": 3, "depth": 0, "door": false})
		if shape.begins_with("bend_"):
			var p: int = int(shape.substr(5))
			put.call(p - 1, 9, "#")
			put.call(p - 1, 10, "#")
			put.call(p + 1, 10, "#")
			put.call(p + 1, 11, "#")
	var anchors: Array = [["landmark", 2, 10, 1, 1, [], "milestone"], ["rubble_heap", 2, 9, 1, 1, [], ""]]
	var text: Array = []
	for y: int in 20:
		text.append("".join(rows[y]))
		for x: int in 20:
			if x % 3 == 0 and y % 3 == 0 and rows[y][x] != "#":
				anchors.append(["timber_hook", x, y, 1, 1, [], ""])
	return {"id": id, "kind": "main_road", "biome": "main_road", "shape": shape, "old_fall": old_fall, "footprint": [1, 1],
		"weight": weight, "rows": text, "anchors": anchors, "stubs": stubs}


## Every main-road shape, then grids and plain fallbacks for every biome: enough for a whole mine.
static func road_pack(problems: Array[String] = []) -> PackedByteArray:
	var specs: Array = [main_road_spec("main_straight", "straight", false), main_road_spec("main_bend_5", "bend_5", false),
		main_road_spec("main_bend_10", "bend_10", false), main_road_spec("main_bend_15", "bend_15", false),
		main_road_spec("main_crossing", "crossing", false), main_road_spec("main_straight_oldfall", "straight", true)]
	for biome: String in ["pit_bottom", "seam", "old_workings", "black_seam", "old_mens"]:
		specs.append(grid_spec("%s_grid" % biome, "biome_cell", biome, 1.0))
		specs.append(grid_spec("%s_plain" % biome, "fallback", biome, 1.0))
	return pack(specs, problems)
