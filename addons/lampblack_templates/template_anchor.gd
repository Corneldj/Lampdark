@tool
class_name TemplateAnchor
extends Marker2D
## One anchor site (GEN-01's types). It sits on the tile under its position, spans `size` tiles
## right and down from there, and must lie in one cell of the footprint.

const TYPES: Array[String] = ["timber_hook", "rubble_heap", "landmark", "chamber", "remains", "item",
	"wall_fixture", "door_site", "trap_site", "low_road", "gas_area", "gas_dead_end", "rich_rock",
	"collapse", "poi_slot"]

@export_enum("timber_hook", "rubble_heap", "landmark", "chamber", "remains", "item", "wall_fixture", "door_site",
	"trap_site", "low_road", "gas_area", "gas_dead_end", "rich_rock", "collapse", "poi_slot") var anchor_type: String = "timber_hook":
	set(value):
		anchor_type = value
		queue_redraw()
@export var size: Vector2i = Vector2i(1, 1):
	set(value):
		size = value
		queue_redraw()
@export var tags: PackedStringArray = PackedStringArray()
## A landmark's, fixture's or slot's kind (a phone wall_fixture is "phone").
@export var kind: String = ""


## The footprint tile it sits on.
func tile() -> Vector2i:
	return Vector2i(floori(position.x / TemplateSource.TILE_PX), floori(position.y / TemplateSource.TILE_PX))


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var origin: Vector2 = Vector2(tile() * TemplateSource.TILE_PX) - position
	var hue: float = float(maxi(TYPES.find(anchor_type), 0)) / float(TYPES.size())
	draw_rect(Rect2(origin, Vector2(size * TemplateSource.TILE_PX)), Color.from_hsv(hue, 0.8, 1.0, 0.9), false, 2.0)
