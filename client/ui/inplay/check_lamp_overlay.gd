class_name CheckLampOverlay
extends Node2D
## UI-01's Check Lamp (Gameplay §4.4): while it is held, a panel over the lower part of the screen (the
## mine still drawn above it) with the lamp in hand side-on: the oil line against lamp.check_marks marks
## (MNR-07's oil in 48ths), the flint notches out of lamp.max_notches, and the flame at full size as the
## owner may see it. A shuttered lamp shows only lit or out. No lamp in hand shows nothing. It needs no
## light and changes nothing (the hold is all the server ever hears). Its content is the inventory's
## lamp record and the own flame byte. Beside the lamp, the own hands and belt (a playtest's ask, a
## design addition to §14.3): the lamp hand, the free hand and the four slots by their keys, the
## selected one marked, a stack's count as pips (never a number), and chalk and the Pocket Book.
## It shows while held even with no lamp in hand.

const W: float = 1920.0
const H: float = 1080.0

## {oil48, notches} (or an electric lamp's {battery5}) while held; {} otherwise.
var check: Dictionary = {}
var lamp_kind: int = 0
var shut: bool = false
var lit: bool = false
## The own hands and belt (ClientConnection.inventory), and the slots' key labels.
var hands: Dictionary = {}
var slot_keys: Array[String] = []


func _init() -> void:
	ScreenElementRegistry.mark(self, &"check_lamp")
	visible = false


## `held`: Check Lamp held this frame; `inventory`: ClientConnection.inventory; `flame`: nonzero when
## the own flame shows (the caller passes the own light's radius above 0: the own block's flame byte
## carries only the flame's states, so it was 0 for a plain lit lamp).
func update(held: bool, inventory: Dictionary, flame: int, store: BindingsStore = null, family: String = "kbm") -> void:
	var lamp: Array = Variants.array(inventory.get("lamp", [0, 0]))
	lamp_kind = int(Variants.number(lamp[0])) if not lamp.is_empty() else 0
	check = Variants.dict(inventory.get("check", {}))
	shut = Variants.flag(inventory.get("lamp_shut", false))
	lit = flame != 0
	hands = inventory
	slot_keys.clear()
	for i: int in 4:
		slot_keys.append(GlyphText.label(store, "slot_%d" % (i + 1), family) if store != null else "")
	visible = held and not inventory.is_empty()
	queue_redraw()


## Whether the lamp part has anything to show (a lamp in hand, its check or its shutter).
func _lamp_shown() -> bool:
	return lamp_kind != 0 and (not check.is_empty() or shut)


func _draw() -> void:
	var height: float = H * Tuning.f(&"camera.check_lamp_panel_height")
	var top: float = H - height
	draw_rect(Rect2(0.0, top, W, height), ScreenElementRegistry.PANEL, true)
	_belt(Vector2(120.0, top + 48.0))
	if not _lamp_shown():
		return
	var cx: float = W * 0.5
	var glass: Rect2 = Rect2(cx - 50.0, top + 40.0, 100.0, height - 110.0)
	# The fount below the glass, holding the oil.
	var fount: Rect2 = Rect2(cx - 70.0, glass.end.y, 140.0, 56.0)
	draw_rect(glass, ScreenElementRegistry.DIM, false, 3.0)
	draw_rect(fount, ScreenElementRegistry.DIM, false, 3.0)
	var font: Font = ThemeDB.fallback_font
	var size: int = ScreenElementRegistry.min_font_px()
	# MNR-08: an electric lamp shows its battery instead of oil and notches: a cell, no number.
	if check.has("battery5"):
		_battery(Rect2(cx + 110.0, top + 40.0, 40.0, height - 80.0), float(Variants.number(check["battery5"])) * 5.0 / Tuning.f(&"lamp.electric_battery"))
		return
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


## The own hands and belt, top to bottom: the lamp hand (and whether it hangs on the belt hook), the
## free hand, then each slot by its key, the selected one marked; chalk and the Pocket Book last.
## Every string is drawn from its text key (UI-01's lint), or is a binding's key label.
func _belt(at: Vector2) -> void:
	var font: Font = ThemeDB.fallback_font
	var size: int = ScreenElementRegistry.min_font_px()
	var step: float = size + 14.0
	var y: float = at.y
	var lamp: Array = Variants.array(hands.get("lamp", [0, 0]))
	var end_x: float = _row(font, size, Vector2(at.x, y), "ui.lamp_hand", "", lamp, false)
	if lamp_kind != 0 and Variants.flag(hands.get("hooked", false)):
		draw_string(font, Vector2(end_x + 16.0, y), UiText.text("ui.on_hook"), HORIZONTAL_ALIGNMENT_LEFT, -1, size, ScreenElementRegistry.DIM)
	y += step
	_row(font, size, Vector2(at.x, y), "ui.free_hand", "", Variants.array(hands.get("free", [0, 0])), false)
	y += step * 1.3
	var slots: Array = Variants.array(hands.get("slots", []))
	var selected: int = int(Variants.number(hands.get("selected", -1)))
	for i: int in slots.size():
		var key_label: String = slot_keys[i] if i < slot_keys.size() else ""
		_row(font, size, Vector2(at.x, y), "", key_label, Variants.array(slots[i]), i == selected)
		y += step
	var x: float = at.x
	for raw: Variant in [["chalk", "ui.chalk"], ["pocket_book", "ui.pocket_book"]]:
		var pair: Array = raw
		if Variants.flag(hands.get(str(pair[0]), false)):
			draw_string(font, Vector2(x, y + step * 0.3), UiText.text(str(pair[1])), HORIZONTAL_ALIGNMENT_LEFT, -1, size, ScreenElementRegistry.DIM)
			x += font.get_string_size(UiText.text(str(pair[1])), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 28.0


## One row: its label (a text key) or a slot's key label, what it holds (its name, or "empty"
## dimmed), the count as pips, a mark if selected. Returns where the item's name ends.
func _row(font: Font, size: int, at: Vector2, label_key: String, key_label: String, item: Array, selected: bool) -> float:
	var empty: bool = item.is_empty() or int(Variants.number(item[0])) == 0
	if selected:
		draw_rect(Rect2(at.x - 30.0, at.y - size * 0.75, 14.0, 14.0), ScreenElementRegistry.INK, true)
	if not label_key.is_empty():
		draw_string(font, at, UiText.text(label_key), HORIZONTAL_ALIGNMENT_LEFT, -1, size, ScreenElementRegistry.DIM)
	else:
		draw_string(font, at, key_label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ScreenElementRegistry.DIM)
	var x: float = at.x + 200.0
	var item_key: String = item_text_key(item)
	draw_string(font, Vector2(x, at.y), UiText.text(item_key), HORIZONTAL_ALIGNMENT_LEFT, -1, size,
		ScreenElementRegistry.DIM if empty else ScreenElementRegistry.INK)
	var w: float = font.get_string_size(UiText.text(item_key), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var count: int = int(Variants.number(item[1])) if item.size() > 1 else 0
	if not empty and count > 1:
		for p: int in count:
			draw_circle(Vector2(x + w + 18.0 + p * 14.0, at.y - size * 0.35), 4.0, ScreenElementRegistry.INK)
	return x + w


## An item's text key: its in-world name ("a spanner"), "empty", or "something" for a kind with no name.
static func item_text_key(item: Array) -> String:
	var kind: int = int(Variants.number(item[0])) if not item.is_empty() else 0
	if kind == 0:
		return "ui.empty"
	var key: String = ItemKinds.text_key(kind)
	return key if not UiText.text(key).is_empty() else "ui.something"


## MNR-08: the battery as a cell filled from the bottom, its terminal on top; no number.
func _battery(cell: Rect2, share: float) -> void:
	draw_rect(cell, ScreenElementRegistry.DIM, false, 3.0)
	draw_rect(Rect2(cell.get_center().x - 8.0, cell.position.y - 10.0, 16.0, 10.0), ScreenElementRegistry.DIM, true)
	var k: float = clampf(share, 0.0, 1.0)
	var inner: Rect2 = cell.grow(-6.0)
	draw_rect(Rect2(inner.position.x, inner.end.y - inner.size.y * k, inner.size.x, inner.size.y * k), ScreenElementRegistry.INK, true)


## The flame side-on, a teardrop, never the world's amber.
func _flame(base: Vector2, tall: float) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in 17:
		var t: float = i / 16.0 * TAU
		points.append(base + Vector2(sin(t) * 14.0, -tall * 0.5 * (1.0 - cos(t)) * (0.6 + 0.4 * absf(sin(t * 0.5)))))
	draw_colored_polygon(points, ScreenElementRegistry.FLAME)
