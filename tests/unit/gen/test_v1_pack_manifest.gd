extends GutTest
## GEN-16: the shipped v1 template set (data/templates/set.json, its export as the readable source of
## truth). At least the v1 counts of each kind, every kind of point of interest the slice's plan
## can call for, and the deep-biome override on. Every cell template carries what GEN-16 asks of
## one: a landmark, one or two rubble heaps, timber hooks, remains, a wall fixture, items and a
## collapse alternate on a road; half the Old Workings' or more hold trap sites, and a third of the
## Seam's chambers or more are high. Each main road's side passages are door sites; the 2x1 kinds
## come with the door on a long side and on a short one; the lair is Old Workings with one stub; the
## hoard is one high chamber; base camp matches GEN-02's fixed file in all four rotations.

const SET: String = "res://data/templates/set.json"
const EXPORT: String = "res://data/templates/export"
const V1_CELLS: Dictionary = {"pit_bottom": 8, "seam": 12, "old_workings": 12}
const SLICE_POIS: Array[String] = ["substation", "electricians_cabin", "stores", "fuel_store", "fitters_shop", "haulage_engine_house",
	"lamp_cabin", "first_aid_station", "hoard", "lair"]
## The contents lines that hold a load (the stretcher; the drum gear, the deep workshop's planned part).
const LOAD_LINES: Dictionary = {"first_aid_station": 1, "deep_workshop": 1}
const WALKABLE: String = ".=~sSdD"

var _all: Array[Dictionary] = []


func before_all() -> void:
	assert_true(Tuning.load_server())
	var current: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(SET)))
	for raw: Variant in Variants.array(current["templates"]):
		var id: String = str(raw)
		var meta: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(EXPORT.path_join(id).path_join("template.json"))))
		var cells: Array[Dictionary] = []
		for c: Variant in Variants.array(meta["cells"]):
			var at: Array = c
			cells.append(Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(EXPORT.path_join(id).path_join("cell_%d_%d.json" % [Variants.whole(at[0]),
				Variants.whole(at[1])])))))
		meta["cell_files"] = cells
		_all.append(meta)


func _of(kind: String, biome: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t: Dictionary in _all:
		if str(t["kind"]) == kind and (biome.is_empty() or str(t["biome"]) == biome):
			out.append(t)
	return out


static func _anchors(t: Dictionary, type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for cell: Dictionary in Variants.array(t["cell_files"]):
		for raw: Variant in Variants.array(cell.get("anchors", [])):
			var a: Dictionary = raw
			if str(a["type"]) == type:
				out.append(a)
	return out


static func _collapses(t: Dictionary) -> int:
	var n: int = 0
	for cell: Dictionary in Variants.array(t["cell_files"]):
		n += Variants.array(cell.get("collapses", [])).size()
	return n


func test_at_least_the_v1_counts_and_every_slice_kind() -> void:
	assert_eq(_of("base_camp").size(), 1, "base camp")
	for biome: String in V1_CELLS.keys():
		assert_gte(_of("biome_cell", biome).size(), Variants.whole(V1_CELLS[biome]), "%s cell templates" % biome)
		assert_eq(_of("fallback", biome).size(), 1, "%s's plain fallback" % biome)
	assert_gte(_of("main_road").size(), 10, "main roads")
	var shapes: Dictionary = {}
	for t: Dictionary in _of("main_road"):
		shapes["%s%s" % [t["shape"], "+old_fall" if Variants.flag(t["old_fall"]) else ""]] = true
	for shape: String in ["straight", "bend_5", "bend_10", "bend_15", "crossing", "straight+old_fall"]:
		assert_true(shapes.has(shape), "a %s main road" % shape)
	var kinds: Dictionary = {}
	for t: Dictionary in _of("poi"):
		kinds[str(t["poi_kind"])] = true
	assert_gte(_of("poi").size(), 10, "points of interest")
	for kind: String in SLICE_POIS:
		assert_true(kinds.has(kind), "a %s template" % kind)
	assert_eq(Tuning.s(&"mine.v1_deep_biome_override"), "old_workings", "the deep-biome override on")
	for ring: Variant in Variants.array(MineLayouts.biome_table()["rings"]):
		for pair: Variant in Variants.array(ring):
			assert_false(["black_seam", "old_mens"].has(str(Variants.array(pair)[0])), "no ring draws a biome GEN-17 brings")


func test_every_cell_template_carries_what_gen16_asks() -> void:
	var cells: Array[Dictionary] = _of("biome_cell")
	cells.append_array(_of("fallback"))
	for t: Dictionary in cells:
		if str(t["id"]) == "seam_crossing_01":
			continue  # GEN-04's hand-made sample, older than the checklist
		var id: String = str(t["id"])
		assert_eq(_anchors(t, "landmark").size(), 1, "%s: one landmark" % id)
		assert_between(_anchors(t, "rubble_heap").size(), 1, 2, "%s: one or two rubble heaps" % id)
		assert_gt(_anchors(t, "timber_hook").size(), 0, "%s: timber hooks" % id)
		assert_gt(_anchors(t, "remains").size(), 0, "%s: remains" % id)
		assert_gt(_anchors(t, "wall_fixture").size(), 0, "%s: a wall fixture" % id)
		assert_gt(_anchors(t, "item").size(), 0, "%s: items" % id)
		assert_gt(_collapses(t), 0, "%s: a collapse alternate" % id)
	var old: Array[Dictionary] = _of("biome_cell", "old_workings")
	var trapped: int = 0
	for t: Dictionary in old:
		trapped += 1 if _anchors(t, "trap_site").size() > 0 else 0
	assert_gte(trapped * 2, old.size(), "half the Old Workings or more hold trap sites")
	var chambers: int = 0
	var high: int = 0
	for t: Dictionary in _of("biome_cell", "seam"):
		for a: Dictionary in _anchors(t, "chamber"):
			chambers += 1
			high += 1 if Variants.array(a.get("tags", [])).has("high") else 0
	assert_gt(chambers, 0, "the Seam's chambers")
	assert_gte(high * 3, chambers, "a third of them or more high")


func test_main_roads_points_of_interest_and_their_doors() -> void:
	for t: Dictionary in _of("main_road"):
		if str(t["shape"]) == "crossing":
			continue
		var sides: int = 0
		for raw: Variant in Variants.array(t["stubs"]):
			var s: Dictionary = raw
			sides += 1 if str(s["edge"]) == "north" or str(s["edge"]) == "south" else 0
		assert_eq(_anchors(t, "door_site").size(), sides, "%s: a door site on every side passage" % t["id"])
	var table: Dictionary = Variants.dict(Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(TemplateBuild.POI_KINDS)))["kinds"])
	var sides_of: Dictionary = {}
	for t: Dictionary in _of("poi"):
		var kind: String = str(t["poi_kind"])
		var row: Dictionary = Variants.dict(table.get(kind, {}))
		assert_gte(_anchors(t, "poi_slot").size(), Variants.whole(row.get("contents_lines", 0)), "%s: a slot for each contents line" % t["id"])
		var doors: Array[Dictionary] = []
		for raw: Variant in Variants.array(t["stubs"]):
			var s: Dictionary = raw
			if Variants.flag(s["door"]):
				doors.append(s)
		assert_gt(doors.size(), 0, "%s: a door stub" % t["id"])
		if Variants.flag(row.get("phone", false)):
			var phone: bool = false
			for a: Dictionary in _anchors(t, "wall_fixture"):
				phone = phone or str(a.get("kind", "")) == "phone"
			assert_true(phone, "%s: its phone" % t["id"])
		var footprint: Array = Variants.array(t["footprint"])
		if Variants.whole(footprint[0]) == 2:
			for s: Dictionary in doors:
				var long: bool = str(s["edge"]) == "north" or str(s["edge"]) == "south"
				sides_of["%s:%s" % [kind, "long" if long else "short"]] = true
	for kind: String in ["substation", "haulage_engine_house"]:
		assert_true(sides_of.has(kind + ":long"), "%s with its door on a long side" % kind)
		assert_true(sides_of.has(kind + ":short"), "and on a short side")
	for t: Dictionary in _of("poi"):
		if str(t["poi_kind"]) == "lair":
			assert_eq(str(t["biome"]), "old_workings", "the lair is Old Workings")
			assert_eq(Variants.array(t["stubs"]).size(), 1, "joining exactly one socket")
		if str(t["poi_kind"]) == "hoard":
			var rooms: Array[Dictionary] = _anchors(t, "chamber")
			assert_eq(rooms.size(), 1, "the hoard is one chamber")
			assert_true(Variants.array(rooms[0].get("tags", [])).has("high"), "high")


## A point of interest's slots in its contents lines' order: cell by cell, each cell's as exported.
static func _slots(t: Dictionary) -> Array[Array]:
	var out: Array[Array] = []
	for cell: Dictionary in Variants.array(t["cell_files"]):
		for raw: Variant in Variants.array(cell.get("anchors", [])):
			var a: Dictionary = raw
			if str(a["type"]) == "poi_slot":
				out.append([cell, a])
	return out


func test_a_loads_slot_has_floor_all_round() -> void:
	# A load lies three tiles end to end, east to west (LoadSegment), however the template is turned.
	var seen: Dictionary = {}
	for t: Dictionary in _of("poi"):
		var kind: String = str(t["poi_kind"])
		if not LOAD_LINES.has(kind):
			continue
		seen[kind] = true
		var slot: Array = _slots(t)[Variants.whole(LOAD_LINES[kind])]
		var tiles: Array = Variants.array(Variants.dict(slot[0])["tiles"])
		var a: Dictionary = slot[1]
		var at: Vector2i = Vector2i(Variants.whole(a["x"]), Variants.whole(a["y"]))
		for step: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = at + step
			assert_true(WALKABLE.contains(str(tiles[q.y])[q.x]), "%s: floor at %s round its load's slot" % [t["id"], q])
	assert_eq(seen.size(), LOAD_LINES.size(), "every kind that holds a load has a template")


static func _tiles_and_anchors(file: Dictionary) -> Dictionary:
	var anchors: Array = []
	for raw: Variant in Variants.array(file.get("anchors", [])):
		var a: Dictionary = raw
		var tags: Array = Variants.array(a.get("tags", [])).duplicate()
		tags.sort()
		anchors.append([str(a["type"]), Variants.whole(a["x"]), Variants.whole(a["y"]), Variants.whole(a.get("w", 1)), Variants.whole(a.get("h", 1)),
			str(a.get("kind", "")), tags])
	anchors.sort()
	return {"tiles": Variants.array(file["tiles"]), "anchors": anchors}


func test_ported_base_camp_matches_the_fixed_file_in_all_four_rotations() -> void:
	var fixed: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/basecamp/cell_0_0.json")))
	var ported: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(EXPORT.path_join("base_camp/cell_0_0.json"))))
	for steps: int in 4:
		assert_eq(_tiles_and_anchors(Basecamp.rotate(ported, steps)), _tiles_and_anchors(Basecamp.rotate(fixed, steps)),
			"rotation %d: the same tiles and anchors" % steps)
