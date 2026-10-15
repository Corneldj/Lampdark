class_name ChalkDecal
extends Node2D
## MNR-10: chalk marks (Gameplay §4.5, §12.7). A drawn tile whose decal byte carries the chalk bit
## (sent only seen at 0.30 or more, VIS-03; never a token) brings its glyph bytes (ChalkMarks): a
## mark on the floor is drawn at the tile's centre, one on a rib face against that face. Arrows
## point their way, an X, a '!' or a digit 0-9. Chalk white (Palette.CHALK_WHITE) shaded by the
## tile's own light, drawn only while seen. Placeholder glyphs until the hand-drawn set (assets).

const DECAL_CHALK: int = 2
const ALPHA: float = 0.95
## A floor glyph's half-size and a face glyph's, as shares of a tile; a face glyph sits this far
## from the tile's centre toward its wall.
const FLOOR_HALF: float = 0.32
const FACE_HALF: float = 0.18
const FACE_OFFSET: float = 0.36

var _drawn: DrawnSet = null
var _view: ReceivedView = null
var _origin: Vector2 = Vector2.ZERO
var _px: float = 64.0


func set_frame(drawn: DrawnSet, view: ReceivedView, origin: Vector2, px: float) -> void:
	_drawn = drawn
	_view = view
	_origin = origin
	_px = px
	queue_redraw()


## The marks drawn now: {tile: PackedByteArray of the five glyph bytes} (tests).
func marks() -> Dictionary:
	var out: Dictionary = {}
	if _drawn == null or _view == null:
		return out
	for raw: Variant in _drawn.tiles.keys():
		var t: Vector2i = raw
		if not _view.tiles.has(t):
			continue
		var rec: PackedByteArray = _view.tiles[t]
		if (rec[2] & DECAL_CHALK) != 0 and rec.size() >= 3 + ChalkMarks.SURFACES:
			out[t] = rec.slice(3, 3 + ChalkMarks.SURFACES)
	return out


## Chalk on a tile lit to `light` (0-1): white shaded like the floor under it.
static func colour_at(light: float) -> Color:
	var k: float = clampf(0.35 + 0.65 * light, 0.0, 1.0)
	return Color(Palette.CHALK_WHITE.r * k, Palette.CHALK_WHITE.g * k, Palette.CHALK_WHITE.b * k, ALPHA)


## Where a surface's glyph is drawn, and its half-size, in tiles from the tile's corner.
static func anchor_of(surface: int) -> Vector2:
	if surface == ChalkMarks.Surface.FLOOR:
		return Vector2(0.5, 0.5)
	var step: Vector2i = ChalkMarks.FACE_STEP[surface]
	return Vector2(0.5, 0.5) + Vector2(step) * FACE_OFFSET


func _draw() -> void:
	var m: Dictionary = marks()
	var w: float = maxf(_px * 0.05, 2.0)
	for raw: Variant in m.keys():
		var t: Vector2i = raw
		var glyphs: PackedByteArray = m[raw]
		var c: Color = colour_at(float(Variants.number(Variants.dict(_drawn.tiles[raw]).get("light", 0.0))))
		for s: int in ChalkMarks.SURFACES:
			var g: int = glyphs[s]
			if g == 0:
				continue
			var half: float = (FLOOR_HALF if s == ChalkMarks.Surface.FLOOR else FACE_HALF) * _px
			var centre: Vector2 = (Vector2(t) + anchor_of(s) - _origin) * _px
			_glyph(ChalkMarks.kind_of(g), ChalkMarks.direction_of(g), centre, half, c, w)


func _glyph(kind: int, direction: int, centre: Vector2, half: float, c: Color, w: float) -> void:
	match kind:
		ChalkMarks.Kind.ARROW:
			var along: Vector2 = TrailDecal.vector_of(direction)
			var tip: Vector2 = centre + along * half
			draw_line(centre - along * half, tip, c, w, true)
			draw_line(tip, tip - along.rotated(0.5) * half * 0.6, c, w, true)
			draw_line(tip, tip - along.rotated(-0.5) * half * 0.6, c, w, true)
		ChalkMarks.Kind.CROSS:
			draw_line(centre + Vector2(-half, -half), centre + Vector2(half, half), c, w, true)
			draw_line(centre + Vector2(-half, half), centre + Vector2(half, -half), c, w, true)
		ChalkMarks.Kind.BANG:
			draw_line(centre + Vector2(0, -half), centre + Vector2(0, half * 0.35), c, w, true)
			draw_circle(centre + Vector2(0, half * 0.8), w * 0.7, c)
		_:
			var digit: String = str(kind - ChalkMarks.Kind.DIGIT_0)
			var font: Font = ThemeDB.fallback_font
			var size: int = maxi(8, roundi(half * 2.0))
			var box: Vector2 = font.get_string_size(digit, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
			draw_string(font, centre + Vector2(-box.x * 0.5, box.y * 0.3), digit, HORIZONTAL_ALIGNMENT_LEFT, -1, size, c)
