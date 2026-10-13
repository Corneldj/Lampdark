class_name ShadowLayer
extends Node2D
## VIS-09: the shadow tell on the client. Each drawn tile's shading (the server's 2 bits in its decal
## byte, bits 6-7) lays a translucent shadow tone over the lit floor: level 1 faint, 3 deepest.
## Never opaque, so a shaded tile stays lit (VIS-05's composite floor keeps it off pure black).
## Draws only on tiles the client draws; it never says what cast it.

const SHADE_SHIFT: int = 6
## The shadow tone's opacity at each level (Proposed placeholder ramp).
const ALPHA: Array[float] = [0.0, 0.22, 0.38, 0.55]

var _drawn: DrawnSet = null
var _view: ReceivedView = null
var _origin: Vector2 = Vector2.ZERO
var _px: float = 64.0


static func level_of(decals: int) -> int:
	return (decals >> SHADE_SHIFT) & 3


func set_frame(drawn: DrawnSet, view: ReceivedView, origin: Vector2, px: float) -> void:
	_drawn = drawn
	_view = view
	_origin = origin
	_px = px
	queue_redraw()


## The shaded tiles drawn now: {tile: level} (tests).
func shaded() -> Dictionary:
	var out: Dictionary = {}
	if _drawn == null or _view == null:
		return out
	for raw: Variant in _drawn.tiles.keys():
		var t: Vector2i = raw
		if _view.tiles.has(t):
			var rec: PackedByteArray = _view.tiles[t]
			var level: int = level_of(rec[2])
			if level > 0:
				out[t] = level
	return out


func _draw() -> void:
	var s: Dictionary = shaded()
	for raw: Variant in s.keys():
		var t: Vector2i = raw
		var c: Color = Palette.SHADOW_TONE
		c.a = ALPHA[int(Variants.number(s[raw]))]
		draw_rect(Rect2((Vector2(t) - _origin) * _px, Vector2(_px, _px)), c)
