class_name MapTableCloseup
extends SheetCloseup
## LFT-14: the map table's close-up (Gameplay §12.7, §14.3; GDD §14.1, §14.5): the crew's shared
## survey sheet, faintly squared, with only the shaft and a north point printed at its centre, north
## up. SheetCloseup does the pencil, the view and the input; this draws the paper and holds the
## zoom to mine.sheet_view_squares_min to _max printed squares across the short side.

const SQUARES: Color = Color(0.62, 0.68, 0.70, 0.35)
const SQUARE_UNITS: float = 256.0

## The zoom as printed squares across the short side (mine.sheet_view_squares when it opens).
var squares_across: float:
	get:
		return view_units / SQUARE_UNITS
	set(v):
		view_units = v * SQUARE_UNITS


func on_open(context: Dictionary) -> void:
	squares_across = Tuning.f(&"mine.sheet_view_squares")
	centre = Vector2.ZERO
	super.on_open(context)


func view_limits() -> Vector2:
	return Vector2(Tuning.f(&"mine.sheet_view_squares_min"), Tuning.f(&"mine.sheet_view_squares_max")) * SQUARE_UNITS


## Faint squares, and the shaft and the north point printed at the centre.
func _draw_paper() -> void:
	var z: float = zoom()
	var spacing_px: float = SQUARE_UNITS * z
	if spacing_px >= 6.0:
		var view: Rect2 = visible_rect()
		var x: float = ceilf(view.position.x / SQUARE_UNITS) * SQUARE_UNITS
		while x <= view.end.x:
			var sx: float = to_screen(Vector2(x, 0)).x
			draw_line(Vector2(sx, 0), Vector2(sx, size.y), SQUARES, 1.0)
			x += SQUARE_UNITS
		var y: float = ceilf(view.position.y / SQUARE_UNITS) * SQUARE_UNITS
		while y <= view.end.y:
			var sy: float = to_screen(Vector2(0, y)).y
			draw_line(Vector2(0, sy), Vector2(size.x, sy), SQUARES, 1.0)
			y += SQUARE_UNITS
	var ink: float = maxf(2.0, Tuning.f(&"mine.pencil_min_px")) * line_weight
	for line: PackedVector2Array in MapCard.printed():
		var on_screen: PackedVector2Array = PackedVector2Array()
		for p: Vector2 in line:
			on_screen.append(to_screen(p))
		draw_polyline(on_screen, PRINT_INK, ink, true)
