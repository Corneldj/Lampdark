class_name DustHaze
extends Node2D
## VIS-09: the moth's dust (Gameplay §7.2): while the frame's dust flag is set, a faint haze with
## specks settling straight down (driftless) over every drawn tile lit to light.dust_min_light, and
## nowhere else, so its edge is the light's, never the moth's. Placeholder look; it must survive
## stream compression, hence the haze under the specks rather than 2 px detail alone.

const HAZE_ALPHA: float = 0.10
const SPECKS_PER_TILE: int = 3
const FALL_TILES_PER_S: float = 0.35

var _tiles: Array[Vector2i] = []
var _origin: Vector2 = Vector2.ZERO
var _px: float = 64.0
var _t: float = 0.0


## The tiles dust shows on now (tests).
func tiles() -> Array[Vector2i]:
	return _tiles


func set_frame(drawn: DrawnSet, view: ReceivedView, origin: Vector2, px: float, now_s: float) -> void:
	_tiles.clear()
	_origin = origin
	_px = px
	_t = now_s
	if drawn != null and view != null and view.dust:
		var min_light: int = roundi(Tuning.f(&"light.dust_min_light") * 255.0) if Tuning.current.has_key(&"light.dust_min_light") else 31
		for raw: Variant in drawn.tiles.keys():
			var t: Vector2i = raw
			if view.tiles.has(t):
				var rec: PackedByteArray = view.tiles[t]
				if rec[0] >= min_light:
					_tiles.append(t)
	queue_redraw()


func _draw() -> void:
	var haze: Color = Palette.DUST_GREY
	haze.a = HAZE_ALPHA
	var speck: Color = Palette.DUST_GREY
	speck.a = 0.45
	for t: Vector2i in _tiles:
		var at: Vector2 = (Vector2(t) - _origin) * _px
		draw_rect(Rect2(at, Vector2(_px, _px)), haze)
		for i: int in SPECKS_PER_TILE:
			var h: int = hash(Vector3i(t.x, t.y, i))
			var fx: float = float(h & 1023) / 1023.0
			var phase: float = float((h >> 10) & 1023) / 1023.0
			var fy: float = fposmod(phase + _t * FALL_TILES_PER_S, 1.0)
			draw_rect(Rect2(at + Vector2(fx, fy) * _px, Vector2(3, 3)), speck)
