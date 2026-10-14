class_name CheckLampOverlay
extends Node2D
## UI-01's Check Lamp (Gameplay §4.4): while it is held, a panel over the lower part of the screen (the
## mine still drawn above it) with the lamp in hand side-on: the oil line against lamp.check_marks marks
## (MNR-07's oil in 48ths), the flint notches out of lamp.max_notches, and the flame at full size as the
## owner may see it. A shuttered lamp shows only lit or out. No lamp in hand shows nothing. It needs no
## light and changes nothing (the hold is all the server ever hears). Its content is the inventory's
## lamp record and the own flame byte.

const W: float = 1920.0
const H: float = 1080.0

## {oil48, notches} while held; {} otherwise.
var check: Dictionary = {}
var lamp_kind: int = 0
var shut: bool = false
var lit: bool = false


func _init() -> void:
	ScreenElementRegistry.mark(self, &"check_lamp")
	visible = false


## `held`: Check Lamp held this frame; `inventory`: ClientConnection.inventory; `flame`: the own
## block's flame byte (FlameFlags).
func update(held: bool, inventory: Dictionary, flame: int) -> void:
	var lamp: Array = Variants.array(inventory.get("lamp", [0, 0]))
	lamp_kind = int(Variants.number(lamp[0])) if not lamp.is_empty() else 0
	check = Variants.dict(inventory.get("check", {}))
	shut = Variants.flag(inventory.get("lamp_shut", false))
	lit = flame != 0
	visible = held and lamp_kind != 0 and (not check.is_empty() or shut)
	queue_redraw()


func _draw() -> void:
	var height: float = H * Tuning.f(&"camera.check_lamp_panel_height")
	var top: float = H - height
	draw_rect(Rect2(0.0, top, W, height), ScreenElementRegistry.PANEL, true)
	var cx: float = W * 0.5
	var glass: Rect2 = Rect2(cx - 50.0, top + 40.0, 100.0, height - 110.0)
	# The fount below the glass, holding the oil.
	var fount: Rect2 = Rect2(cx - 70.0, glass.end.y, 140.0, 56.0)
	draw_rect(glass, ScreenElementRegistry.DIM, false, 3.0)
	draw_rect(fount, ScreenElementRegistry.DIM, false, 3.0)
	var font: Font = ThemeDB.fallback_font
	var size: int = ScreenElementRegistry.min_font_px()
	if shut:
		draw_string(font, Vector2(cx + 110.0, glass.get_center().y), UiText.text("ui.lamp_lit" if lit else "ui.lamp_out"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, ScreenElementRegistry.INK)
		return
	if lit:
		_flame(Vector2(cx, glass.end.y - 10.0), glass.size.y * 0.6)
	# The oil line against its marks, on a gauge beside the fount: no number, a line and marks.
	var gauge: Rect2 = Rect2(cx + 110.0, top + 40.0, 24.0, height - 80.0)
	draw_rect(gauge, ScreenElementRegistry.DIM, false, 2.0)
	var marks: int = maxi(1, roundi(Tuning.f(&"lamp.check_marks")))
	for i: int in range(1, marks + 1):
		var y: float = gauge.end.y - gauge.size.y * i / float(marks)
		draw_line(Vector2(gauge.position.x - 10.0, y), Vector2(gauge.position.x, y), ScreenElementRegistry.DIM, 3.0)
	var oil: float = clampf(float(Variants.number(check.get("oil48", 0))) / 48.0, 0.0, 1.0)
	var oil_y: float = gauge.end.y - gauge.size.y * oil
	draw_line(Vector2(gauge.position.x, oil_y), Vector2(gauge.end.x, oil_y), ScreenElementRegistry.INK, 4.0)
	# The flint's notches: a row of slots, the used ones filled.
	var notches: int = int(Variants.number(check.get("notches", 0)))
	var slots: int = maxi(1, roundi(Tuning.f(&"lamp.max_notches")))
	for i: int in slots:
		var r: Rect2 = Rect2(cx - 150.0 - i * 30.0, fount.position.y + 16.0, 20.0, 24.0)
		if i < notches:
			draw_rect(r, ScreenElementRegistry.INK, true)
		else:
			draw_rect(r, ScreenElementRegistry.DIM, false, 2.0)


## The flame side-on, a teardrop, never the world's amber.
func _flame(base: Vector2, tall: float) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in 17:
		var t: float = i / 16.0 * TAU
		points.append(base + Vector2(sin(t) * 14.0, -tall * 0.5 * (1.0 - cos(t)) * (0.6 + 0.4 * absf(sin(t * 0.5)))))
	draw_colored_polygon(points, ScreenElementRegistry.FLAME)
