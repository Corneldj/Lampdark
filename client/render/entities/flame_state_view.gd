class_name FlameStateView
extends Node2D
## VIS-08 (GDD §14.1, §14.5): a flame's states drawn as distinct moving shapes, never only colour,
## so each reads in a greyscale render: trembling shivers in place without leaning; guttering sinks
## low and squat and flickers; the blue cap rings the top; shrinking draws it small; the flare-up
## stands tall and thin. Tremble and gutter animate below light.max_flash_hz (3 Hz). Shapes are in
## flame-local pixels, the base 8 px wide and 20 px tall, tip up (negative y). The flags come only
## from the server (an identity record, or the own block); the one exception is NET-10's host
## migration, which calls set_migration_gutter: the gutter shape, no sputter, no radius change.

const BASE_W: float = 8.0
const BASE_H: float = 20.0
const POINTS: int = 14

var flags: int = 0
var time_s: float = 0.0
var _migration_gutter: bool = false


## NET-10 only: host migration's 5-10 s of client-drawn guttering.
func set_migration_gutter(on: bool) -> void:
	_migration_gutter = on
	queue_redraw()


## The states drawn: the server's, plus migration's gutter shape.
func shown_flags() -> int:
	return flags | (FlameFlags.GUTTER if _migration_gutter else 0)


## The sputter plays for a real guttering flame only (SND-03 reads this), never for migration.
func sputtering() -> bool:
	return (flags & FlameFlags.GUTTER) != 0


## How fast a state's shape moves, Hz: below the flash cap.
static func animation_hz(state: int) -> float:
	var cap: float = Tuning.f(&"light.max_flash_hz")
	match state:
		FlameFlags.TREMBLE:
			return cap * 0.8
		FlameFlags.GUTTER:
			return cap * 0.5
	return 0.0


## The polygons for `bits` at time `t`: the flame body, then the cap's band when capped.
static func shapes(bits: int, t: float) -> Array[PackedVector2Array]:
	var w: float = BASE_W
	var h: float = BASE_H
	if (bits & FlameFlags.FLARE_UP) != 0:
		w *= 0.6
		h *= 2.2
	if (bits & FlameFlags.GUTTER) != 0:
		w *= 1.25
		h *= 0.45 + 0.12 * sin(TAU * animation_hz(FlameFlags.GUTTER) * t)
	if (bits & FlameFlags.SHRINK) != 0:
		w *= 0.6
		h *= 0.6
	var body: PackedVector2Array = PackedVector2Array()
	var tremble: bool = (bits & FlameFlags.TREMBLE) != 0
	for i: int in POINTS:
		var a: float = TAU * float(i) / POINTS
		# A teardrop: round at the base, drawn up to a tip.
		var x: float = sin(a) * w * 0.5 * (1.0 - 0.6 * maxf(0.0, cos(a)))
		var y: float = -(1.0 - cos(a)) * 0.5 * h
		if tremble:
			# Neighbouring points shiver in opposite directions: in place, never a lean.
			var side: float = 1.0 if i % 2 == 0 else -1.0
			x += side * 1.6 * sin(TAU * animation_hz(FlameFlags.TREMBLE) * t + float(i))
		body.append(Vector2(x, y))
	var out: Array[PackedVector2Array] = [body]
	if (bits & FlameFlags.CAP) != 0:
		out.append(_cap_band(w, h))
	return out


## A thin arched band ringing the flame's top.
static func _cap_band(w: float, h: float) -> PackedVector2Array:
	var band: PackedVector2Array = PackedVector2Array()
	var outer: float = w * 0.9
	var inner: float = w * 0.6
	var top: float = -h - 2.0
	for i: int in 9:
		var a: float = PI * float(i) / 8.0
		band.append(Vector2(cos(a) * outer, top - sin(a) * outer * 0.6))
	for i: int in range(8, -1, -1):
		var a: float = PI * float(i) / 8.0
		band.append(Vector2(cos(a) * inner, top - sin(a) * inner * 0.6))
	return band


func _process(delta: float) -> void:
	time_s += delta
	if (shown_flags() & (FlameFlags.TREMBLE | FlameFlags.GUTTER)) != 0:
		queue_redraw()


func _draw() -> void:
	var bits: int = shown_flags()
	var polys: Array[PackedVector2Array] = shapes(bits, time_s)
	var body: Color = Color(0.55, 0.75, 1.0) if (bits & FlameFlags.FLARE_UP) != 0 else Color(1.0, 0.72, 0.3)
	draw_colored_polygon(polys[0], body)
	if polys.size() > 1:
		draw_colored_polygon(polys[1], Color(0.7, 0.85, 1.0))
