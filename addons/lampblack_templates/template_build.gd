@tool
class_name TemplateBuild
extends RefCounted
## GEN-04: a TemplateSource scene to a template (the export's shape, cells as LbCellData with
## their zones cut), its validation through the native validator, and its canonical export text:
## <id>/template.json (the metadata) beside one GEN-01 cell file per cell (CellFile's schema).
## Everything is sorted, so identical scenes give identical bytes on every machine.

const FORMAT: int = 1
const EDGES: Array[String] = ["north", "east", "south", "west"]
## The point-of-interest kinds' table (GEN-09 writes it; read when present).
const POI_KINDS: String = "res://data/world/poi_kinds.json"


## {"template": Dictionary, "errors": Array[String]}: the template, or why the scene cannot be one.
## `rules` (rules()) gives the standard stub depth for stubs left at 0.
static func build(src: TemplateSource, rules_in: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var label: String = "template %s" % src.template_id
	if src.template_id.is_empty():
		errors.append("%s: no template_id" % label)
	var size: Vector2i = src.footprint
	if size.x < 1 or size.y < 1 or size.x > 2 or size.y > 2:
		errors.append("%s: footprint %s is not 1x1, 1x2, 2x1 or 2x2" % [label, size])
		return {"template": {}, "errors": errors}
	var tiles_w: int = size.x * WorldIds.CELL_TILES
	var tiles_h: int = size.y * WorldIds.CELL_TILES
	var rows: Array[PackedStringArray] = []
	for y: int in tiles_h:
		var row: PackedStringArray = PackedStringArray()
		row.resize(tiles_w)
		row.fill("#")
		rows.append(row)
	var geometry: TileMapLayer = src.get_node_or_null("Geometry") as TileMapLayer
	if geometry == null:
		errors.append("%s: no Geometry tile layer" % label)
		return {"template": {}, "errors": errors}
	for at: Vector2i in geometry.get_used_cells():
		var ch: String = char_at(geometry, at, &"char")
		if not _inside(at, tiles_w, tiles_h):
			errors.append("%s: tile (%d, %d) is outside the footprint" % [label, at.x, at.y])
		elif not CellFile.CHARS.has(ch):
			errors.append("%s: tile (%d, %d) is not a palette tile" % [label, at.x, at.y])
		else:
			var row: PackedStringArray = rows[at.y]
			row[at.x] = ch
			rows[at.y] = row
	var cell_anchors: Dictionary = {}
	var collapses: Dictionary = {}
	var stubs: Array[Dictionary] = []
	for child: Node in src.get_children():
		if child is TemplateAnchor:
			_add_anchor(child as TemplateAnchor, size, cell_anchors, errors, label)
		elif child is TemplateStub:
			stubs.append(_stub(child as TemplateStub, int(Variants.number(rules_in.get("stub_depth", 0)))))
		elif child is TemplateCollapse:
			_add_collapse(child as TemplateCollapse, geometry, rows, size, collapses, errors, label)
	var rib: Array[Dictionary] = []
	var rib_layer: TileMapLayer = src.get_node_or_null("Rib") as TileMapLayer
	if rib_layer != null:
		for at: Vector2i in rib_layer.get_used_cells():
			if not _inside(at, tiles_w, tiles_h):
				errors.append("%s: rib tile (%d, %d) is outside the footprint" % [label, at.x, at.y])
				continue
			var cell: Vector2i = Vector2i(at.x / WorldIds.CELL_TILES, at.y / WorldIds.CELL_TILES)
			var local: Vector2i = at - cell * WorldIds.CELL_TILES
			rib.append({"cell": [cell.x, cell.y], "index": local.y * WorldIds.CELL_TILES + local.x,
				"milli": int(Variants.number(rib_layer.get_cell_tile_data(at).get_custom_data(&"milli")))})
	rib.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _key(a, ["cell", "index"]) < _key(b, ["cell", "index"]))
	stubs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _stub_key(a) < _stub_key(b))
	if not errors.is_empty():
		return {"template": {}, "errors": errors}
	var room_kind: String = "chamber"
	if src.kind == "poi":
		room_kind = "poi"
	elif src.kind == "base_camp":
		room_kind = "base_camp"
	var cells: Array = []
	for cy: int in size.y:
		for cx: int in size.x:
			var c: Vector2i = Vector2i(cx, cy)
			var lines: Array = []
			for y: int in WorldIds.CELL_TILES:
				lines.append("".join(rows[cy * WorldIds.CELL_TILES + y].slice(cx * WorldIds.CELL_TILES, (cx + 1) * WorldIds.CELL_TILES)))
			var anchors: Array = Variants.array(cell_anchors.get(c, []))
			anchors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _anchor_key(a) < _anchor_key(b))
			var cell_collapses: Array = Variants.array(collapses.get(c, []))
			cell_collapses.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
			var data: LbCellData = CellFile.from_dict({"format": CellFile.FORMAT, "cell": [cx, cy], "tiles": lines, "anchors": anchors,
				"collapses": cell_collapses}, label)
			if data == null:
				errors.append("%s: cell (%d, %d) did not load" % [label, cx, cy])
				continue
			data.cut_zones(room_kind)
			cells.append(data)
	var template: Dictionary = {"id": src.template_id, "kind": src.kind, "biome": src.biome, "footprint": [size.x, size.y],
		"poi_kind": src.poi_kind, "shape": "" if src.shape == "none" else src.shape, "old_fall": src.old_fall, "weight": src.weight, "author_version": src.author_version,
		"stubs": stubs, "rib": rib, "cells": cells}
	return {"template": template if errors.is_empty() else {}, "errors": errors}


## A layer tile's custom data field ("char" or "milli"), as text; "" for an empty tile.
static func char_at(layer: TileMapLayer, at: Vector2i, field: StringName) -> String:
	var data: TileData = layer.get_cell_tile_data(at)
	if data == null:
		return ""
	return str(data.get_custom_data(field))


## The validator's numbers: tuning's (mine.*, tapper.reach_tiles, hazards.*), the standard stub
## depth, and the point-of-interest kinds' table when there is one (POI_KINDS: GEN-09's contents
## lines and LFT-12's phones: {"lair_kind": "lair", "kinds": {kind: {"contents_lines": n,
## "phone": bool}}}). `extra` overrides any of them.
static func rules(tuning: TuningSet, extra: Dictionary = {}) -> Dictionary:
	var params: Dictionary = {
		"stub_depth": roundi(tuning.f(&"mine.stub_throat_depth_tiles")),
		"road_width_min": roundi(tuning.f(&"mine.road_width_min_tiles")),
		"road_width_max": roundi(tuning.f(&"mine.road_width_max_tiles")),
		"chamber_min": roundi(tuning.f(&"mine.chamber_min_tiles")),
		"chamber_max": roundi(tuning.f(&"mine.chamber_max_tiles")),
		"chamber_forbidden_width": roundi(tuning.f(&"mine.chamber_forbidden_width_tiles")),
		"rib_wander_max_milli": roundi(tuning.f(&"mine.rib_wander_max_tiles") * 1000.0),
		"tapper_reach_milli": roundi(tuning.f(&"tapper.reach_tiles") * 1000.0),
		"hook_reach_tiles": roundi(tuning.f(&"mine.timber_hook_reach_tiles")),
		"rubble_min": roundi(tuning.f(&"mine.rubble_heaps_min")),
		"rubble_max": roundi(tuning.f(&"mine.rubble_heaps_max")),
		"rich_rock_min_thickness": roundi(tuning.f(&"mine.rich_rock_min_thickness_tiles")),
		"gas_area_min": roundi(tuning.f(&"hazards.firedamp_pocket_min_tiles")),
		"gas_area_max": roundi(tuning.f(&"hazards.firedamp_pocket_max_tiles")),
		"gas_dead_end_min": roundi(tuning.f(&"hazards.blackdamp_road_min_tiles")),
		"gas_dead_end_max": roundi(tuning.f(&"hazards.blackdamp_road_max_tiles")),
		"collapse_length_max": roundi(tuning.f(&"mine.collapse_length_max_tiles")),
		"biome_widths_max": tuning.table(&"mine.biome_socket_widths_max"),
		"main_road_width": roundi(tuning.f(&"mine.main_road_width_tiles")),
		"main_road_offset": roundi(tuning.f(&"mine.main_road_edge_offset_tiles")),
		"bend_reach": roundi(tuning.f(&"mine.main_road_bend_reach_tiles")),
	}
	if FileAccess.file_exists(POI_KINDS):
		var table: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(POI_KINDS)))
		var slots: Dictionary = {}
		var phones: Array = []
		var kinds: Dictionary = Variants.dict(table.get("kinds", {}))
		for kind: Variant in kinds.keys():
			var row: Dictionary = Variants.dict(kinds[kind])
			slots[str(kind)] = int(Variants.number(row.get("contents_lines", 0)))
			if Variants.flag(row.get("phone", false)):
				phones.append(str(kind))
		params["poi_slots"] = slots
		params["poi_phone_kinds"] = phones
		params["lair_kind"] = str(table.get("lair_kind", "lair"))
	params.merge(extra, true)
	return params


## Every problem as text naming the template, the rule and the tile. The stub width limit is the
## template's biome's (GEN-06's table in params["biome_widths_max"]).
static func validate(template: Dictionary, params: Dictionary) -> Array[String]:
	var own: Dictionary = params.duplicate()
	var limits: Dictionary = Variants.dict(params.get("biome_widths_max", {}))
	if limits.has(str(template.get("biome", ""))):
		own["biome_stub_width_max"] = int(Variants.number(limits[str(template["biome"])]))
	var out: Array[String] = []
	for raw: Variant in LbTemplates.validate(template, own):
		out.append(str(Variants.dict(raw)["text"]))
	return out


## The template's export files: {"<id>/template.json": text, "<id>/cell_<x>_<y>.json": text}.
static func files(template: Dictionary) -> Dictionary:
	var id: String = str(template["id"])
	var out: Dictionary = {}
	var cells: Array = []
	for raw: Variant in Variants.array(template["cells"]):
		var data: LbCellData = raw as LbCellData
		var c: Vector2i = data.get_coord()
		cells.append([c.x, c.y])
		out["%s/cell_%d_%d.json" % [id, c.x, c.y]] = CellFile.serialize(data)
	var lines: PackedStringArray = PackedStringArray(["{"])
	lines.append("\t\"format\": %d," % FORMAT)
	for key: String in ["id", "kind", "biome", "footprint", "poi_kind", "shape", "old_fall", "weight", "author_version"]:
		lines.append("\t\"%s\": %s," % [key, JSON.stringify(template.get(key, "" if key == "shape" else false))])
	lines.append("\t\"cells\": %s," % JSON.stringify(cells))
	for key: String in ["stubs", "rib"]:
		var items: Array = Variants.array(template[key])
		lines.append("\t\"%s\": [" % key)
		for i: int in items.size():
			lines.append("\t\t%s%s" % [JSON.stringify(items[i]), "," if i < items.size() - 1 else ""])
		lines.append("\t]%s" % ("," if key == "stubs" else ""))
	lines.append("}")
	out["%s/template.json" % id] = "\n".join(lines) + "\n"
	return out


## A template read back from its export folder (dir/<id>/...), for the pack and round trips.
static func load_export(dir: String) -> Dictionary:
	var meta: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("template.json"))))
	if meta.is_empty() or int(Variants.number(meta.get("format", 0))) != FORMAT:
		push_error("TemplateBuild: %s has no template.json of format %d" % [dir, FORMAT])
		return {}
	var cells: Array = []
	for raw: Variant in Variants.array(meta.get("cells", [])):
		var c: Array = Variants.array(raw)
		var data: LbCellData = CellFile.load_file(dir.path_join("cell_%d_%d.json" % [int(Variants.number(c[0])), int(Variants.number(c[1]))]))
		if data == null:
			return {}
		cells.append(data)
	var template: Dictionary = {}
	for key: String in ["id", "kind", "biome", "poi_kind", "shape"]:
		template[key] = str(meta.get(key, ""))
	template["old_fall"] = Variants.flag(meta.get("old_fall", false))
	var footprint: Array = Variants.array(meta.get("footprint", [1, 1]))
	template["footprint"] = [int(Variants.number(footprint[0])), int(Variants.number(footprint[1]))]
	template["weight"] = float(Variants.number(meta.get("weight", 1.0)))
	template["author_version"] = int(Variants.number(meta.get("author_version", 1)))
	var stubs: Array = []
	for raw: Variant in Variants.array(meta.get("stubs", [])):
		var s: Dictionary = Variants.dict(raw)
		var cell: Array = Variants.array(s.get("cell", [0, 0]))
		stubs.append({"cell": [int(Variants.number(cell[0])), int(Variants.number(cell[1]))], "edge": str(s.get("edge", "")),
			"offset": int(Variants.number(s.get("offset", 0))), "max_width": int(Variants.number(s.get("max_width", 0))),
			"depth": int(Variants.number(s.get("depth", 2))), "door": Variants.flag(s.get("door", false))})
	template["stubs"] = stubs
	var rib: Array = []
	for raw: Variant in Variants.array(meta.get("rib", [])):
		var r: Dictionary = Variants.dict(raw)
		var cell: Array = Variants.array(r.get("cell", [0, 0]))
		rib.append({"cell": [int(Variants.number(cell[0])), int(Variants.number(cell[1]))], "index": int(Variants.number(r.get("index", 0))),
			"milli": int(Variants.number(r.get("milli", 0)))})
	template["rib"] = rib
	template["cells"] = cells
	return template


static func _inside(at: Vector2i, w: int, h: int) -> bool:
	return at.x >= 0 and at.y >= 0 and at.x < w and at.y < h


static func _add_anchor(a: TemplateAnchor, size: Vector2i, out: Dictionary, errors: Array[String], label: String) -> void:
	var at: Vector2i = a.tile()
	var cell: Vector2i = Vector2i(floori(float(at.x) / WorldIds.CELL_TILES), floori(float(at.y) / WorldIds.CELL_TILES))
	var last: Vector2i = at + a.size - Vector2i.ONE
	var last_cell: Vector2i = Vector2i(floori(float(last.x) / WorldIds.CELL_TILES), floori(float(last.y) / WorldIds.CELL_TILES))
	if a.size.x < 1 or a.size.y < 1 or cell != last_cell or not _inside(cell, size.x, size.y):
		errors.append("%s: anchor %s %s at tile (%d, %d) is not inside one cell of the footprint" % [label, a.anchor_type, a.name, at.x, at.y])
		return
	var local: Vector2i = at - cell * WorldIds.CELL_TILES
	var tags: Array = Array(a.tags)
	tags.sort()
	if not out.has(cell):
		out[cell] = []
	Variants.array(out[cell]).append({"type": a.anchor_type, "x": local.x, "y": local.y, "w": a.size.x, "h": a.size.y,
		"tags": tags, "kind": a.kind})


static func _add_collapse(layer: TemplateCollapse, geometry: TileMapLayer, rows: Array[PackedStringArray], size: Vector2i,
		out: Dictionary, errors: Array[String], label: String) -> void:
	var used: Array[Vector2i] = layer.get_used_cells()
	used.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	if used.is_empty():
		errors.append("%s: collapse %d has no fallen tiles" % [label, layer.collapse_id])
		return
	var cell: Vector2i = Vector2i(floori(float(used[0].x) / WorldIds.CELL_TILES), floori(float(used[0].y) / WorldIds.CELL_TILES))
	var standing: Array = []
	var fallen: Array = []
	for at: Vector2i in used:
		var here: Vector2i = Vector2i(floori(float(at.x) / WorldIds.CELL_TILES), floori(float(at.y) / WorldIds.CELL_TILES))
		var ch: String = char_at(layer, at, &"char")
		if here != cell or not _inside(here, size.x, size.y) or not CellFile.CHARS.has(ch):
			errors.append("%s: collapse %d tile (%d, %d) is not a palette tile in its one cell" % [label, layer.collapse_id, at.x, at.y])
			return
		var local: Vector2i = at - cell * WorldIds.CELL_TILES
		var index: int = local.y * WorldIds.CELL_TILES + local.x
		var under: String = rows[at.y][at.x] if geometry != null else "#"
		standing.append([index, under])
		fallen.append([index, ch])
	if not out.has(cell):
		out[cell] = []
	for other: Variant in Variants.array(out[cell]):
		if int(Variants.dict(other)["id"]) == layer.collapse_id:
			errors.append("%s: two collapses numbered %d" % [label, layer.collapse_id])
			return
	Variants.array(out[cell]).append({"id": layer.collapse_id, "standing": standing, "fallen": fallen, "is_fallen": false})


static func _stub(s: TemplateStub, standard: int) -> Dictionary:
	return {"cell": [s.cell.x, s.cell.y], "edge": s.edge, "offset": s.offset, "max_width": s.max_width,
		"depth": s.depth if s.depth > 0 else standard, "door": s.door}


static func _stub_key(s: Dictionary) -> Array:
	var cell: Array = Variants.array(s["cell"])
	return [cell[1], cell[0], EDGES.find(str(s["edge"])), s["offset"]]


static func _anchor_key(a: Dictionary) -> Array:
	return [a["y"], a["x"], TemplateAnchor.TYPES.find(str(a["type"])), a["w"], a["h"], a["kind"], ",".join(PackedStringArray(Variants.array(a["tags"])))]


static func _key(d: Dictionary, keys: Array[String]) -> Array:
	var out: Array = []
	for k: String in keys:
		var v: Variant = d[k]
		if v is Array:
			var pair: Array = v
			out.append(pair[1])
			out.append(pair[0])
		else:
			out.append(v)
	return out
