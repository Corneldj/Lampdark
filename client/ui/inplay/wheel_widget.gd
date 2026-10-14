class_name WheelWidget
extends Node2D
## UI-01's generic wheel (Gameplay §4.8, §6.7): slices with text keys (slice 0 straight up, clockwise,
## as MNR-15's WheelInput.slice counts them), optional band rings at SND-11's voice.wheel_ring_bounds
## (inner whisper, middle talk, outer shout), the centre that cancels, and the live pick highlighted.
## MNR-15 resolves the pick and holds facing; the slices' owners act on it. Its content is slice keys,
## the rings flag and the pick vector.

const SLICES: Dictionary = {
	"callout": ["callout.here", "callout.help", "callout.is_that_you", "callout.count_off", "callout.douse",
		"callout.light_up", "callout.quiet", "callout.gate", "callout.oil", "callout.moth", "callout.tapping", "callout.stythe"],
	"job_page": ["callout.now", "callout.right", "callout.stop", "callout.left"],
	"signal": ["wheel.signal.one", "wheel.signal.two", "wheel.signal.three", "wheel.signal.circle"],
	"chalk": ["wheel.chalk.arrow", "wheel.chalk.cross", "wheel.chalk.bang", "wheel.chalk.0", "wheel.chalk.1", "wheel.chalk.2",
		"wheel.chalk.3", "wheel.chalk.4", "wheel.chalk.5", "wheel.chalk.6", "wheel.chalk.7", "wheel.chalk.8", "wheel.chalk.9"],
}

var slices: Array[String] = []
var rings: bool = false
var radius_px: float = 194.0
## The pick (MNR-15's vec, 1.0 at the edge).
var vec: Vector2 = Vector2.ZERO


func _init() -> void:
	ScreenElementRegistry.mark(self, &"wheel")
	visible = false


## The slices for a wheel: "callout" (or its job page), "signal", "chalk", or "combined" (the pad's
## one wheel of lamp signals and chalk).
static func slices_for(kind: String, job_page: bool = false) -> Array[String]:
	var out: Array[String] = []
	var lists: Array = [kind] if kind != "combined" else ["signal", "chalk"]
	for list: Variant in lists:
		var name: String = "job_page" if str(list) == "callout" and job_page else str(list)
		for k: Variant in Variants.array(SLICES.get(name, [])):
			out.append(str(k))
	return out


func show_wheel(on: bool, centre: Vector2, keys: Array[String], with_rings: bool, pick_vec: Vector2, short_side: float) -> void:
	visible = on and not keys.is_empty()
	position = centre
	slices = keys
	rings = with_rings
	vec = pick_vec
	radius_px = Tuning.f(&"ui.wheel_radius") * short_side
	queue_redraw()


## The highlighted slice (-1 when centred) and band ring (0 inner .. 2 outer; -1 without rings).
func picked() -> Vector2i:
	if vec.length() < WheelInput.cancel_radius() or slices.is_empty():
		return Vector2i(-1, -1)
	var s: int = WheelInput.slice(fposmod(rad_to_deg(vec.angle()), 360.0), slices.size())
	var band: int = -1
	if rings:
		var bounds: PackedFloat64Array = Tuning.current.list_f(&"voice.wheel_ring_bounds")
		band = 0
		for i: int in range(1, bounds.size()):
			if vec.length() >= bounds[i]:
				band = i
	return Vector2i(s, band)


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var size: int = ScreenElementRegistry.min_font_px()
	var n: int = slices.size()
	var width: float = TAU / n
	var pick: Vector2i = picked()
	var bounds: PackedFloat64Array = Tuning.current.list_f(&"voice.wheel_ring_bounds")
	draw_circle(Vector2.ZERO, radius_px, ScreenElementRegistry.PANEL)
	for i: int in n:
		# Slice i is centred on straight up plus i widths, clockwise (screen space, +y down).
		var mid: float = -PI * 0.5 + i * width
		if i == pick.x:
			var inner: float = radius_px * (bounds[pick.y] if rings and pick.y >= 0 else bounds[0])
			var outer: float = radius_px * (bounds[pick.y + 1] if rings and pick.y + 1 < bounds.size() else 1.0)
			var poly: PackedVector2Array = PackedVector2Array()
			for k: int in 9:
				poly.append(Vector2.from_angle(mid - width * 0.5 + width * k / 8.0) * outer)
			for k: int in 9:
				poly.append(Vector2.from_angle(mid + width * 0.5 - width * k / 8.0) * inner)
			draw_colored_polygon(poly, Color(ScreenElementRegistry.INK, 0.25))
		var edge: float = mid - width * 0.5
		draw_line(Vector2.from_angle(edge) * radius_px * bounds[0], Vector2.from_angle(edge) * radius_px, ScreenElementRegistry.DIM, 2.0)
		var text: String = UiText.text(slices[i])
		var at: Vector2 = Vector2.from_angle(mid) * radius_px * 0.72
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		draw_string(font, at - Vector2(w * 0.5, -size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size,
			ScreenElementRegistry.INK if i == pick.x else ScreenElementRegistry.DIM)
	if rings:
		for i: int in range(1, bounds.size()):
			draw_arc(Vector2.ZERO, radius_px * bounds[i], 0.0, TAU, 64, ScreenElementRegistry.DIM, 2.0, true)
	# The centre that cancels.
	draw_arc(Vector2.ZERO, radius_px * bounds[0], 0.0, TAU, 48, ScreenElementRegistry.INK, 3.0, true)
	draw_arc(Vector2.ZERO, radius_px, 0.0, TAU, 96, ScreenElementRegistry.INK, 3.0, true)
