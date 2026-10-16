@tool
class_name TemplateCollapse
extends TileMapLayer
## One collapse alternate: paint its fallen tiles (rock across the road's full width, 1 to 3 tiles
## long) on this layer. Its standing tiles are the Geometry layer's under them. Its fallen zones
## and portals are cut on export. All its tiles lie in one cell.

@export var collapse_id: int = 1
