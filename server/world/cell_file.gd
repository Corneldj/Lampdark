class_name CellFile
## Fixed cell files (GEN-01): data/maps/<map>/cell_<cx>_<cy>.json. GEN-04 exports templates in
## the same schema, so there is one loader. The writer is canonical, so a loaded file
## re-serialises byte for byte. Server-only (client presets exclude data/maps/).
##
## The road_graph field is SND-01's zone and portal block as JSON (RoadGraphBlock); each tile's
## zone is in "zones". A collapse cut by GEN-04's template pipeline also carries its fallen state:
## "zones" ([[index, standing zone, fallen zone], ...]) and "fallen_road_graph" (the cell's whole
## block with it fallen); a collapse without them has neither key. Tile characters: '.' floor, '=' floor with rails, '~' sump mud, '#' rock, 'c' coal,
## 'B' brick, 'T' timber, 'S' shut gate, 's' open gate, 'D' shut air door, 'd' open air door.

const FORMAT: int = 1
const STATE_OPEN: int = 1
const STATE_RAIL: int = 2
const STATE_MUD: int = 4

## char -> [material, state]
const CHARS: Dictionary = {
	".": [WorldIds.TileMaterial.FLOOR, 0],
	"=": [WorldIds.TileMaterial.FLOOR, STATE_RAIL],
	"~": [WorldIds.TileMaterial.FLOOR, STATE_MUD],
	"#": [WorldIds.TileMaterial.ROCK, 0],
	"c": [WorldIds.TileMaterial.COAL, 0],
	"B": [WorldIds.TileMaterial.BRICK, 0],
	"T": [WorldIds.TileMaterial.TIMBER, 0],
	"S": [WorldIds.TileMaterial.STEEL, 0],
	"s": [WorldIds.TileMaterial.STEEL, STATE_OPEN],
	"D": [WorldIds.TileMaterial.WOODEN_DOOR, 0],
	"d": [WorldIds.TileMaterial.WOODEN_DOOR, STATE_OPEN],
}


static func path_for(map_name: String, cell: Vector2i) -> String:
	return "res://data/maps/%s/cell_%d_%d.json" % [map_name, cell.x, cell.y]


## Parses a cell file. Returns null and reports errors on a malformed file.
static func load_file(path: String) -> LbCellData:
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("CellFile: %s is not a JSON object" % path)
		return null
	return from_dict(Variants.dict(parsed), path)


static func from_dict(file: Dictionary, label: String) -> LbCellData:
	var data: LbCellData = LbCellData.new()
	var coord: Array = Variants.array(file.get("cell", []))
	if coord.size() != 2 or int(Variants.number(file.get("format", 0))) != FORMAT:
		push_error("CellFile: %s needs format %d and a cell [cx, cy]" % [label, FORMAT])
		return null
	data.set_coord(Vector2i(int(Variants.number(coord[0])), int(Variants.number(coord[1]))))
	var rows: Array = Variants.array(file.get("tiles", []))
	var zones: Array = Variants.array(file.get("zones", []))
	if rows.size() != WorldIds.CELL_TILES:
		push_error("CellFile: %s needs %d tile rows" % [label, WorldIds.CELL_TILES])
		return null
	for y: int in WorldIds.CELL_TILES:
		var row: String = str(rows[y])
		var zone_row: Array = Variants.array(zones[y]) if y < zones.size() else []
		if row.length() != WorldIds.CELL_TILES:
			push_error("CellFile: %s row %d is not %d tiles" % [label, y, WorldIds.CELL_TILES])
			return null
		for x: int in WorldIds.CELL_TILES:
			var pair: Array = Variants.array(CHARS.get(row[x], []))
			if pair.is_empty():
				push_error("CellFile: %s has an unknown tile '%s' at (%d, %d)" % [label, row[x], x, y])
				return null
			var zone: int = int(Variants.number(zone_row[x])) if x < zone_row.size() else 0
			data.set_tile(Vector2i(x, y), int(Variants.number(pair[0])), int(Variants.number(pair[1])), zone)
	for raw: Variant in Variants.array(file.get("anchors", [])):
		var a: Dictionary = Variants.dict(raw)
		var tags: PackedStringArray = PackedStringArray()
		for tag: Variant in Variants.array(a.get("tags", [])):
			tags.append(str(tag))
		if not data.add_anchor(str(a.get("type", "")), Vector2i(int(Variants.number(a.get("x", 0))), int(Variants.number(a.get("y", 0)))),
				Vector2i(int(Variants.number(a.get("w", 1))), int(Variants.number(a.get("h", 1)))), tags, str(a.get("kind", ""))):
			return null
	for raw: Variant in Variants.array(file.get("barriers", [])):
		var b: Dictionary = Variants.dict(raw)
		data.add_barrier(int(Variants.number(b.get("id", 0))), int(Variants.number(b.get("portal", 0))),
			_indices(b.get("tiles", [])), Variants.flag(b.get("open", false)))
	for raw: Variant in Variants.array(file.get("collapses", [])):
		var c: Dictionary = Variants.dict(raw)
		var standing: Array = _writes(c.get("standing", []))
		var fallen: Array = _writes(c.get("fallen", []))
		var standing_indices: PackedInt32Array = standing[0]
		var standing_materials: PackedByteArray = standing[1]
		var fallen_indices: PackedInt32Array = fallen[0]
		var fallen_materials: PackedByteArray = fallen[1]
		var collapse_id: int = int(Variants.number(c.get("id", 0)))
		data.add_collapse(collapse_id, standing_indices, standing_materials,
			fallen_indices, fallen_materials, Variants.flag(c.get("is_fallen", false)))
		if c.has("zones") or c.has("fallen_road_graph"):
			var cut: Array[PackedInt32Array] = _zone_writes(c.get("zones", []))
			data.set_collapse_zones(collapse_id, cut[0], cut[1], cut[2], RoadGraphBlock.encode(Variants.dict(c.get("fallen_road_graph", {}))))
	data.set_road_graph(RoadGraphBlock.encode(Variants.dict(file.get("road_graph", {}))))
	return data


## The canonical text of a cell: fixed key order, one tile row and one object per line.
static func serialize(data: LbCellData) -> String:
	var lines: PackedStringArray = PackedStringArray()
	var coord: Vector2i = data.get_coord()
	lines.append("{")
	lines.append("\t\"format\": %d," % FORMAT)
	lines.append("\t\"cell\": [%d, %d]," % [coord.x, coord.y])
	lines.append("\t\"tiles\": [")
	var zone_rows: PackedStringArray = PackedStringArray()
	for y: int in WorldIds.CELL_TILES:
		var row: String = ""
		var zone_row: PackedStringArray = PackedStringArray()
		for x: int in WorldIds.CELL_TILES:
			var tile: Dictionary = data.get_tile(Vector2i(x, y))
			row += _char_for(int(Variants.number(tile["material"])), int(Variants.number(tile["state"])))
			zone_row.append(str(int(Variants.number(tile["zone"]))))
		lines.append("\t\t\"%s\"%s" % [row, "," if y < WorldIds.CELL_TILES - 1 else ""])
		zone_rows.append("\t\t[%s]%s" % [", ".join(zone_row), "," if y < WorldIds.CELL_TILES - 1 else ""])
	lines.append("\t],")
	lines.append("\t\"zones\": [")
	lines.append_array(zone_rows)
	lines.append("\t],")
	_append_objects(lines, "anchors", data.get_anchors(), func(a: Dictionary) -> Dictionary:
		return {"type": a["type"], "x": a["x"], "y": a["y"], "w": a["w"], "h": a["h"], "tags": Variants.list(a["tags"]), "kind": a["kind"]})
	_append_objects(lines, "barriers", data.get_barriers(), func(b: Dictionary) -> Dictionary:
		return {"id": b["id"], "portal": b["portal"], "tiles": Variants.list(b["tiles"]), "open": b["open"]})
	_append_objects(lines, "collapses", data.get_collapses(), func(c: Dictionary) -> Dictionary:
		var shaped: Dictionary = {"id": c["id"], "standing": _write_pairs(c["standing"]), "fallen": _write_pairs(c["fallen"]), "is_fallen": c["is_fallen"]}
		var zones: Array = Variants.array(c.get("zones", []))
		var block: PackedByteArray = c.get("fallen_road_graph", PackedByteArray())
		if not zones.is_empty() or not block.is_empty():
			shaped["zones"] = zones
			shaped["fallen_road_graph"] = RoadGraphBlock.decode(block)
		return shaped)
	lines.append("\t\"road_graph\": %s" % JSON.stringify(RoadGraphBlock.decode(data.get_road_graph())))
	lines.append("}")
	return "\n".join(lines) + "\n"


## A cell's tiles as CellFile's characters, one string per row.
static func rows_of(data: LbCellData) -> PackedStringArray:
	var rows: PackedStringArray = PackedStringArray()
	for y: int in WorldIds.CELL_TILES:
		var row: String = ""
		for x: int in WorldIds.CELL_TILES:
			var tile: Dictionary = data.get_tile(Vector2i(x, y))
			row += _char_for(int(Variants.number(tile["material"])), int(Variants.number(tile["state"])))
		rows.append(row)
	return rows


static func save(data: LbCellData, path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(serialize(data))
	file.close()
	return OK


static func _append_objects(lines: PackedStringArray, key: String, items: Array, shape: Callable) -> void:
	lines.append("\t\"%s\": [" % key)
	for i: int in items.size():
		var shaped: Dictionary = shape.call(Variants.dict(items[i]))
		lines.append("\t\t%s%s" % [JSON.stringify(shaped), "," if i < items.size() - 1 else ""])
	lines.append("\t],")


static func _char_for(material: int, state: int) -> String:
	for ch: Variant in CHARS.keys():
		var pair: Array = CHARS[ch]
		if int(Variants.number(pair[0])) == material and int(Variants.number(pair[1])) == (state & 7):
			return str(ch)
	return "#"


## [[index, char], ...] -> [PackedInt32Array, PackedByteArray]
static func _writes(raw: Variant) -> Array:
	var indices: PackedInt32Array = PackedInt32Array()
	var materials: PackedByteArray = PackedByteArray()
	for item: Variant in Variants.array(raw):
		var pair: Array = Variants.array(item)
		indices.append(int(Variants.number(pair[0])))
		var spec: Array = Variants.array(CHARS.get(str(pair[1]), [WorldIds.TileMaterial.ROCK, 0]))
		materials.append(int(Variants.number(spec[0])))
	return [indices, materials]


static func _write_pairs(raw: Variant) -> Array:
	var out: Array = []
	for item: Variant in Variants.array(raw):
		var pair: Array = Variants.array(item)
		out.append([int(Variants.number(pair[0])), _char_for(int(Variants.number(pair[1])), 0)])
	return out


## [[index, standing, fallen], ...] -> [indices, standing zones, fallen zones]
static func _zone_writes(raw: Variant) -> Array[PackedInt32Array]:
	var indices: PackedInt32Array = PackedInt32Array()
	var standing: PackedInt32Array = PackedInt32Array()
	var fallen: PackedInt32Array = PackedInt32Array()
	for item: Variant in Variants.array(raw):
		var triple: Array = Variants.array(item)
		if triple.size() == 3:
			indices.append(int(Variants.number(triple[0])))
			standing.append(int(Variants.number(triple[1])))
			fallen.append(int(Variants.number(triple[2])))
	return [indices, standing, fallen]


static func _indices(raw: Variant) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for item: Variant in Variants.array(raw):
		out.append(int(Variants.number(item)))
	return out
