@tool
class_name TemplateSource
extends Node2D
## GEN-04's authoring root: one cell template, drawn in the editor and saved as
## data/templates/src/<kind>/<biome>/<id>.tscn. Its children:
##   - "Geometry", a TileMapLayer painted from the palette (CellFile's tile characters: floor,
##     rails, mud, rock, coal, brick, timber, gates, air doors); unpainted tiles are rock;
##   - "Rib", an optional TileMapLayer of rib-edge art offsets, on solid tiles beside floor;
##   - TemplateAnchor markers (GEN-01's anchor types), TemplateStub openings, and one
##     TemplateCollapse layer per collapse alternate, painted with its fallen tiles.
## Zones and portals are cut by rule on export (GEN-04's zone cutter), collapse alternates included.
## Tiles are TILE_PX pixels; tile (0, 0) is the footprint's top-left.

const TILE_PX: int = 16

@export var template_id: String = "":
	set(value):
		template_id = value
		queue_redraw()
@export_enum("biome_cell", "main_road", "poi", "fallback", "base_camp") var kind: String = "biome_cell"
@export var biome: String = "seam"
## In cells: 1x1, 1x2, 2x1 or 2x2.
@export var footprint: Vector2i = Vector2i(1, 1):
	set(value):
		footprint = value
		queue_redraw()
@export var poi_kind: String = ""
## A main road's shape (GEN-07), drawn east to west: its bend's position, or a crossing ("none"
## for every other kind).
@export_enum("none", "straight", "bend_5", "bend_10", "bend_15", "crossing") var shape: String = "none"
## A straight main road choked at its middle, with exits north at 5 and south at 15.
@export var old_fall: bool = false
@export var weight: float = 1.0
@export var author_version: int = 1


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var side: float = float(WorldIds.CELL_TILES * TILE_PX)
	for cy: int in footprint.y:
		for cx: int in footprint.x:
			draw_rect(Rect2(cx * side, cy * side, side, side), Color(1.0, 0.8, 0.2, 0.9), false, 2.0)
	for t: int in range(5, WorldIds.CELL_TILES * maxi(footprint.x, footprint.y), 5):
		var at: float = float(t * TILE_PX)
		if t % WorldIds.CELL_TILES != 0:
			draw_line(Vector2(at, 0.0), Vector2(at, footprint.y * side), Color(1.0, 1.0, 1.0, 0.08), 1.0)
			draw_line(Vector2(0.0, at), Vector2(footprint.x * side, at), Color(1.0, 1.0, 1.0, 0.08), 1.0)
