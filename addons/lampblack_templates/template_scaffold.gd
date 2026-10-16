@tool
class_name TemplateScaffold
extends RefCounted
## TemplateSource scenes made for the designer: an empty one (all rock, ready to carve) for the
## dock's New button, and one from ASCII rows (CellFile's tile characters) for test fixtures.

const PALETTE: String = "res://addons/lampblack_templates/palette.tres"
## The palette's first row, in atlas order; its second row is RIB_MILLI's rib offsets.
const CHAR_ORDER: Array[String] = [".", "=", "~", "#", "c", "B", "T", "S", "s", "D", "d"]
const RIB_MILLI: Array[int] = [50, 100, 150, 200, 250]
const SRC_DIR: String = "res://data/templates/src"


static func path_for(id: String, kind: String, biome: String) -> String:
	return SRC_DIR.path_join(kind).path_join(biome).path_join(id + ".tscn")


## A footprint of rock with its Geometry and Rib layers.
static func empty(id: String, kind: String, biome: String, footprint: Vector2i) -> TemplateSource:
	var rows: Array = []
	for y: int in footprint.y * WorldIds.CELL_TILES:
		rows.append("#".repeat(footprint.x * WorldIds.CELL_TILES))
	return from_spec({"id": id, "kind": kind, "biome": biome, "footprint": [footprint.x, footprint.y], "rows": rows})


## spec: {id, kind, biome, footprint [w, h], poi_kind, weight, author_version, rows (footprint tiles),
## anchors [[type, x, y, w, h, tags, kind]], stubs [{cell, edge, offset, max_width, depth, door}],
## collapses [{id, tiles: [[x, y, char]]}], rib [[x, y, milli]]}; positions in footprint tiles.
static func from_spec(spec: Dictionary) -> TemplateSource:
	var palette: TileSet = load(PALETTE) as TileSet
	var src: TemplateSource = TemplateSource.new()
	src.template_id = str(spec.get("id", ""))
	src.name = src.template_id if not src.template_id.is_empty() else "Template"
	src.kind = str(spec.get("kind", "biome_cell"))
	src.biome = str(spec.get("biome", "seam"))
	var footprint: Array = Variants.array(spec.get("footprint", [1, 1]))
	src.footprint = Vector2i(int(Variants.number(footprint[0])), int(Variants.number(footprint[1])))
	src.poi_kind = str(spec.get("poi_kind", ""))
	src.shape = str(spec.get("shape", "")) if not str(spec.get("shape", "")).is_empty() else "none"
	src.old_fall = Variants.flag(spec.get("old_fall", false))
	src.weight = float(Variants.number(spec.get("weight", 1.0)))
	src.author_version = int(Variants.number(spec.get("author_version", 1)))
	var geometry: TileMapLayer = _layer("Geometry", palette, src)
	var rows: Array = Variants.array(spec.get("rows", []))
	for y: int in rows.size():
		var row: String = str(rows[y])
		for x: int in row.length():
			geometry.set_cell(Vector2i(x, y), 0, Vector2i(maxi(CHAR_ORDER.find(row[x]), 0), 0))
	var rib: TileMapLayer = _layer("Rib", palette, src)
	for raw: Variant in Variants.array(spec.get("rib", [])):
		var r: Array = Variants.array(raw)
		rib.set_cell(Vector2i(int(Variants.number(r[0])), int(Variants.number(r[1]))), 0,
			Vector2i(maxi(RIB_MILLI.find(int(Variants.number(r[2]))), 0), 1))
	for raw: Variant in Variants.array(spec.get("anchors", [])):
		var a: Array = Variants.array(raw)
		var marker: TemplateAnchor = TemplateAnchor.new()
		marker.anchor_type = str(a[0])
		marker.name = "%s_%d_%d" % [marker.anchor_type, int(Variants.number(a[1])), int(Variants.number(a[2]))]
		marker.position = (Vector2(Variants.number(a[1]), Variants.number(a[2])) + Vector2(0.5, 0.5)) * TemplateSource.TILE_PX
		marker.size = Vector2i(int(Variants.number(a[3])), int(Variants.number(a[4])))
		marker.tags = PackedStringArray(Variants.array(a[5]) if a.size() > 5 else [])
		marker.kind = str(a[6]) if a.size() > 6 else ""
		_own(src, marker)
	for raw: Variant in Variants.array(spec.get("stubs", [])):
		var s: Dictionary = Variants.dict(raw)
		var stub: TemplateStub = TemplateStub.new()
		var cell: Array = Variants.array(s.get("cell", [0, 0]))
		stub.cell = Vector2i(int(Variants.number(cell[0])), int(Variants.number(cell[1])))
		stub.edge = str(s.get("edge", "north"))
		stub.offset = int(Variants.number(s.get("offset", 10)))
		stub.max_width = int(Variants.number(s.get("max_width", 3)))
		stub.depth = int(Variants.number(s.get("depth", 0)))
		stub.door = Variants.flag(s.get("door", false))
		stub.name = "stub_%s_%d" % [stub.edge, stub.offset]
		_own(src, stub)
	for raw: Variant in Variants.array(spec.get("collapses", [])):
		var c: Dictionary = Variants.dict(raw)
		var layer: TemplateCollapse = TemplateCollapse.new()
		layer.collapse_id = int(Variants.number(c.get("id", 1)))
		layer.name = "collapse_%d" % layer.collapse_id
		layer.tile_set = palette
		for t: Variant in Variants.array(c.get("tiles", [])):
			var tile: Array = Variants.array(t)
			layer.set_cell(Vector2i(int(Variants.number(tile[0])), int(Variants.number(tile[1]))), 0,
				Vector2i(maxi(CHAR_ORDER.find(str(tile[2])), 0), 0))
		_own(src, layer)
	return src


## Saves `src` as a scene (its children owned by it). The node is left as it was.
static func save(src: TemplateSource, path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var scene: PackedScene = PackedScene.new()
	var err: Error = scene.pack(src)
	if err != OK:
		return err
	return ResourceSaver.save(scene, path)


static func _layer(layer_name: String, palette: TileSet, src: TemplateSource) -> TileMapLayer:
	var layer: TileMapLayer = TileMapLayer.new()
	layer.name = layer_name
	layer.tile_set = palette
	layer.z_index = -1  # under the template's cell borders and the markers
	if layer_name == "Rib":
		layer.modulate = Color(1.0, 1.0, 1.0, 0.7)
	_own(src, layer)
	return layer


static func _own(src: TemplateSource, child: Node) -> void:
	src.add_child(child)
	child.owner = src
