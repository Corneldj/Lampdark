class_name ArcWidget
extends Node2D
## UI-01's arc (shared with UI-03's captions): a short arc on a circle round the own miner, centred on a
## direction, never a distance (Gameplay §5.5, §14.3). Its content is a bearing in degrees, clockwise
## from east in screen space, or none.

const SPAN_DEG: float = 40.0
const WIDTH: float = 5.0

var bearing_deg: float = 0.0
var radius_px: float = 80.0
var shown: bool = false


func _init() -> void:
	ScreenElementRegistry.mark(self, &"arc")


func set_arc(on: bool, centre: Vector2, bearing: float, radius: float) -> void:
	shown = on
	position = centre
	bearing_deg = bearing
	radius_px = radius
	visible = on
	queue_redraw()


func _draw() -> void:
	if not shown:
		return
	var mid: float = deg_to_rad(bearing_deg)
	var half: float = deg_to_rad(SPAN_DEG * 0.5)
	draw_arc(Vector2.ZERO, radius_px, mid - half, mid + half, 24, ScreenElementRegistry.INK, WIDTH, true)
