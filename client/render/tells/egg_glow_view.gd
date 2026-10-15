class_name EggGlowView
extends Node2D
## VIS-10: the egg-glow's hatch tell (Gameplay §8.3, GDD §14.5). Egg-glow itself is a light like any
## other (VIS-06 draws its pale green-white); once CRT-06 raises the hatch tell, its tiles arrive with
## the hatch bit and this layer swings their brightness at marks.egg_glow_pulse_hz (kept below 3 Hz).
## A visual modulation only: no grid value or seen set changes, and nothing here carries a time.

## The swing's strength: the pale green-white laid over at most this opacity.
const DEPTH: float = 0.35
const MAX_HZ: float = 2.9

var _drawn: DrawnSet = null
var _origin: Vector2 = Vector2.ZERO
var _px: float = 64.0
var _now: float = 0.0


func set_frame(drawn: DrawnSet, origin: Vector2, px: float, now_s: float) -> void:
	_drawn = drawn
	_origin = origin
	_px = px
	_now = now_s
	queue_redraw()


## The tiles pulsing now (tests).
func pulsing() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if _drawn == null:
		return out
	for raw: Variant in _drawn.tiles.keys():
		if Variants.flag(Variants.dict(_drawn.tiles[raw]).get("hatch", false)):
			out.append(raw)
	return out


static func pulse_hz() -> float:
	return minf(Tuning.f(&"marks.egg_glow_pulse_hz"), MAX_HZ)


## The overlay's opacity at time `t` (0 to DEPTH, a smooth swing at pulse_hz).
static func level_at(t: float) -> float:
	return DEPTH * 0.5 * (1.0 - cos(TAU * pulse_hz() * t))


func _draw() -> void:
	var tiles: Array[Vector2i] = pulsing()
	if tiles.is_empty():
		return
	var c: Color = Palette.EGG_GLOW
	c.a = level_at(_now)
	for t: Vector2i in tiles:
		draw_rect(Rect2((Vector2(t) - _origin) * _px, Vector2(_px, _px)), c)
