class_name TrailDecal
extends Node2D
## VIS-10: blood trails (Gameplay §5.8, GDD §12.8). A drawn tile whose decal byte carries the blood
## bit (sent only at 0.12 or more, VIS-03) gets a streaked umber smear along its direction (bits 3-5:
## 0 east, clockwise): three streaks, each at least 3 px wide at 1280x800, so it reads in greyscale
## apart from bare floor and from chalk, and shows the way the body went. Lit by the tile's own light
## like the floor under it (drawn before the composite), and never pure black.

const DECAL_BLOOD: int = 1
const DIR_SHIFT: int = 3
const DIR_MASK: int = 0x38
## Streaks across a tile, and their width as a share of a tile (at least 3 px at 1280x800).
const STREAKS: int = 3
const WIDTH_SHARE: float = 0.09
const ALPHA: float = 0.9

var _drawn: DrawnSet = null
var _view: ReceivedView = null
var _origin: Vector2 = Vector2.ZERO
var _px: float = 64.0


static func direction_of(decals: int) -> int:
	return (decals & DIR_MASK) >> DIR_SHIFT


## The unit vector of a trail direction (0 east, clockwise with +y down).
static func vector_of(direction: int) -> Vector2:
	return Vector2.RIGHT.rotated(posmod(direction, 8) * PI / 4.0)


func set_frame(drawn: DrawnSet, view: ReceivedView, origin: Vector2, px: float) -> void:
	_drawn = drawn
	_view = view
	_origin = origin
	_px = px
	queue_redraw()


## The trail tiles drawn now: {tile: direction} (tests).
func smears() -> Dictionary:
	var out: Dictionary = {}
	if _drawn == null or _view == null:
		return out
	for raw: Variant in _drawn.tiles.keys():
		var t: Vector2i = raw
		if _view.tiles.has(t):
			var rec: PackedByteArray = _view.tiles[t]
			if (rec[2] & DECAL_BLOOD) != 0:
				out[t] = direction_of(rec[2])
	return out


## The streak width in this layer's pixels: at least 3 px once the 1080p world is shown at 800 rows.
func streak_width() -> float:
	return maxf(_px * WIDTH_SHARE, 3.0 * 1080.0 / 800.0)


## The smear's colour on a tile lit to `light` (0-1): umber shaded like the floor, never pure black.
static func colour_at(light: float) -> Color:
	var k: float = clampf(light, 0.0, 1.0)
	var c: Color = Color(maxf(Palette.BLOOD_UMBER.r * k, 2.0 / 255.0), maxf(Palette.BLOOD_UMBER.g * k, 1.0 / 255.0),
		maxf(Palette.BLOOD_UMBER.b * k, 1.0 / 255.0))
	c.a = ALPHA
	return c


func _draw() -> void:
	var s: Dictionary = smears()
	var w: float = streak_width()
	for raw: Variant in s.keys():
		var t: Vector2i = raw
		var c: Color = colour_at(float(Variants.number(Variants.dict(_drawn.tiles[raw]).get("light", 0.0))))
		var along: Vector2 = vector_of(int(Variants.number(s[raw])))
		var across: Vector2 = Vector2(-along.y, along.x)
		var centre: Vector2 = (Vector2(t) + Vector2(0.5, 0.5) - _origin) * _px
		for i: int in STREAKS:
			# Streaks of uneven length, offset across the drag: a smear, not a stripe.
			var offset: float = (float(i) - (STREAKS - 1) * 0.5) * _px * 0.24
			var half: float = _px * (0.46 - 0.08 * absf(float(i) - 1.0))
			var mid: Vector2 = centre + across * offset
			draw_line(mid - along * half, mid + along * half, c, w, true)
