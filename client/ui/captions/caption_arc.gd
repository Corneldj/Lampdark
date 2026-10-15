class_name CaptionArc
extends ArcWidget
## UI-03's edge arc: a noise.caption_arc_deg segment of the ellipse inscribed in the view, centred on
## a sound's bearing from the own miner. The same size at any distance: it says where, never how far.
## Diffuse tells get none.

var radii: Vector2 = Vector2(900.0, 480.0)


func _init() -> void:
	super()


## Shows the arc at `bearing` (degrees clockwise from east) on the ellipse of `half_size`, centred on
## `centre` (the screen's centre), or hides it.
func show_bearing(on: bool, centre: Vector2, bearing: float, half_size: Vector2) -> void:
	radii = half_size
	set_arc(on, centre, bearing, minf(half_size.x, half_size.y))


## The arc's points: the ellipse's points from bearing - span/2 to bearing + span/2.
static func segment(bearing: float, ellipse: Vector2, span_deg: float, steps: int = 24) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for i: int in steps + 1:
		var a: float = deg_to_rad(bearing - span_deg * 0.5 + span_deg * i / steps)
		var d: Vector2 = Vector2(cos(a), sin(a))
		var r: float = 1.0 / sqrt(pow(d.x / ellipse.x, 2.0) + pow(d.y / ellipse.y, 2.0))
		out.append(d * r)
	return out


static func span() -> float:
	return Tuning.f(&"noise.caption_arc_deg") if Tuning.current.has_key(&"noise.caption_arc_deg") else ArcWidget.SPAN_DEG


func _draw() -> void:
	if not shown:
		return
	draw_polyline(segment(bearing_deg, radii, span()), ScreenElementRegistry.INK, ArcWidget.WIDTH, true)
