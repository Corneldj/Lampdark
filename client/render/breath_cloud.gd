class_name BreathCloud
extends Node2D
## SND-06: the private breath-cloud at the own miner's mouth (Gameplay §6.3): the own voice's band
## as measured, never another miner's band and never whether anyone heard. Silent shows nothing; a
## whisper a thin wisp, talk a small cloud, a shout a full one, a scream a torn one. It fades
## between shapes over voice.breath_cloud_fade_s. One per client, on the own miner's overlay, fed
## only from this client's own measurement: nothing about it is sent or received. Placeholder
## shapes drawn in code until painted ones exist.

const TINT: Color = Color(0.9, 0.9, 0.92, 0.6)

var band: int = 0
var _prev_band: int = 0
var _changed_s: float = -INF
var _now_s: float = 0.0
var _px: float = 64.0
var _show: bool = true


## The own band (VoiceBands), as it changes.
func set_band(b: int, now_s: float) -> void:
	if b == band:
		return
	_prev_band = band
	band = b
	_changed_s = now_s
	queue_redraw()


## Each frame: the own miner's screen position, facing (unit), tile size and time.
func set_frame(show_it: bool, miner_px: Vector2, facing: Vector2, px: float, now_s: float) -> void:
	_show = show_it
	_px = px
	_now_s = now_s
	position = miner_px + facing * Tuning.f(&"voice.breath_cloud_offset_tiles") * px
	rotation = facing.angle()
	queue_redraw()


## 0 to 1: how far the current shape has faded in.
func fade() -> float:
	var span: float = Tuning.f(&"voice.breath_cloud_fade_s")
	if span <= 0.0:
		return 1.0
	return clampf((_now_s - _changed_s) / span, 0.0, 1.0)


func _draw() -> void:
	if not _show:
		return
	var k: float = fade()
	if k < 1.0:
		_shape(_prev_band, 1.0 - k)
	_shape(band, k)


## The four shapes, in tile units ahead of the mouth (x forward).
func _shape(b: int, alpha: float) -> void:
	if alpha <= 0.0 or b <= 0:
		return
	var c: Color = Color(TINT, TINT.a * alpha)
	var s: float = _px
	match b:
		1:  # a thin wisp
			var pts: PackedVector2Array = PackedVector2Array()
			for i: int in 7:
				var t: float = i / 6.0
				pts.append(Vector2(t * 0.35, sin(t * PI * 1.5) * 0.05) * s)
			draw_polyline(pts, c, maxf(1.0, s * 0.03), true)
		2:  # a small cloud
			for p: Vector3 in [Vector3(0.1, 0.0, 0.07), Vector3(0.2, -0.04, 0.06), Vector3(0.2, 0.05, 0.05)]:
				draw_circle(Vector2(p.x, p.y) * s, p.z * s, c)
		3:  # a full cloud
			for p: Vector3 in [Vector3(0.12, 0.0, 0.1), Vector3(0.25, -0.08, 0.1), Vector3(0.26, 0.08, 0.09),
					Vector3(0.38, 0.0, 0.11), Vector3(0.36, -0.13, 0.07), Vector3(0.35, 0.14, 0.07)]:
				draw_circle(Vector2(p.x, p.y) * s, p.z * s, c)
		4:  # a torn cloud: ragged, with pieces flung loose
			for p: Vector3 in [Vector3(0.12, 0.0, 0.1), Vector3(0.27, -0.1, 0.09), Vector3(0.28, 0.1, 0.08),
					Vector3(0.42, -0.02, 0.1), Vector3(0.55, -0.16, 0.05), Vector3(0.58, 0.15, 0.04),
					Vector3(0.68, 0.02, 0.035), Vector3(0.75, -0.08, 0.025)]:
				draw_circle(Vector2(p.x, p.y) * s, p.z * s, c)
