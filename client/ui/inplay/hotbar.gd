class_name Hotbar
extends Node2D
## The own hands and belt as a standard hotbar along the bottom of the screen, always shown in play
## (the first playtest, at the designer's request for standard implementations; Gameplay §14.3 notes
## it as Proposed): the lamp hand and the free hand, then the four belt slots by their keys, the
## selected one framed, each item as its grey-box shape (EntityRenderer.draw_item), a stack's count
## as pips (never a number). A lamp on the belt hook shows small with its hook; a lit one, its flame.
## The selected item's name shows above the bar for a moment when the selection changes. Hidden in
## the Dark, while Check Lamp is held and in a close-up. Its content is the inventory record only.

const BOX: float = 72.0
const GAP: float = 8.0
## The gap between the hands and the belt.
const SPLIT: float = 24.0
const BOTTOM: float = 24.0

## ClientConnection.inventory.
var hands: Dictionary = {}
var slot_keys: Array[String] = []
var lamp_lit: bool = false
## The selected slot's name key while it shows ("" otherwise), and until when (s).
var name_key: String = ""
var _name_until: float = -1.0
var _last_selected: int = -1
var _last_kinds: Array = []


func _init() -> void:
	ScreenElementRegistry.mark(self, &"hotbar")
	visible = false


## One frame. `shown`: play is on screen (not the Dark, Check Lamp or a close-up).
func update(shown: bool, inventory: Dictionary, lit: bool, store: BindingsStore, family: String, now_s: float) -> void:
	hands = inventory
	lamp_lit = lit
	slot_keys.clear()
	for i: int in 4:
		slot_keys.append(GlyphText.label(store, "slot_%d" % (i + 1), family) if store != null else "")
	var selected: int = int(Variants.number(inventory.get("selected", -1)))
	var kinds: Array = []
	for raw: Variant in Variants.array(inventory.get("slots", [])):
		kinds.append(int(Variants.number(Variants.array(raw)[0])) if not Variants.array(raw).is_empty() else 0)
	# The selected item's name, for a moment, when the selection or what it holds changes.
	if _last_selected >= 0 and (selected != _last_selected or kinds != _last_kinds) and selected >= 0 and selected < kinds.size():
		var kind: int = int(Variants.number(kinds[selected]))
		name_key = ItemKinds.text_key(kind) if kind != ItemKinds.Kind.NONE else ""
		_name_until = now_s + Tuning.f(&"camera.hotbar_name_s")
	_last_selected = selected
	_last_kinds = kinds
	if now_s >= _name_until:
		name_key = ""
	visible = shown and not inventory.is_empty()
	queue_redraw()


## The left edge of the bar and its top, on the 1920x1080 canvas.
static func origin() -> Vector2:
	var width: float = BOX * 6.0 + GAP * 4.0 + SPLIT
	return Vector2((ScreenElementRegistry.CANVAS.x - width) * 0.5, ScreenElementRegistry.CANVAS.y - BOTTOM - BOX)


## The box of hotbar position `i` (0 the lamp hand, 1 the free hand, 2-5 the belt slots).
static func box(i: int) -> Rect2:
	var at: Vector2 = origin()
	var x: float = at.x + i * (BOX + GAP) + (SPLIT if i >= 2 else 0.0)
	return Rect2(x, at.y, BOX, BOX)


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var size: int = ScreenElementRegistry.min_font_px()
	var lamp: Array = Variants.array(hands.get("lamp", [0, 0]))
	var free: Array = Variants.array(hands.get("free", [0, 0]))
	var hooked: bool = Variants.flag(hands.get("hooked", false))
	_slot(box(0), lamp, false, 0.8 if hooked else 1.0)
	if hooked and _kind(lamp) != ItemKinds.Kind.NONE:
		var r: Rect2 = box(0)
		draw_arc(r.position + Vector2(r.size.x - 14.0, 14.0), 7.0, 0.0, PI * 1.3, 8, ScreenElementRegistry.DIM, 2.0)
	if lamp_lit and _kind(lamp) != ItemKinds.Kind.NONE:
		draw_circle(box(0).get_center() + Vector2(0.0, -BOX * 0.16), 5.0, ScreenElementRegistry.FLAME)
	_slot(box(1), free, false, 1.0)
	draw_string(font, box(0).position + Vector2(0.0, BOX + size), UiText.text("hotbar.lamp"), HORIZONTAL_ALIGNMENT_LEFT, -1, size - 4,
		ScreenElementRegistry.DIM)
	draw_string(font, box(1).position + Vector2(0.0, BOX + size), UiText.text("hotbar.hand"), HORIZONTAL_ALIGNMENT_LEFT, -1, size - 4,
		ScreenElementRegistry.DIM)
	var slots: Array = Variants.array(hands.get("slots", []))
	var selected: int = int(Variants.number(hands.get("selected", -1)))
	for i: int in mini(slots.size(), 4):
		var r: Rect2 = box(i + 2)
		_slot(r, Variants.array(slots[i]), i == selected, 1.0)
		var key_label: String = slot_keys[i] if i < slot_keys.size() else ""
		draw_string(font, r.position + Vector2(6.0, size * 0.85), key_label, HORIZONTAL_ALIGNMENT_LEFT, -1, size - 4, ScreenElementRegistry.DIM)
	if not name_key.is_empty() and selected >= 0 and selected < 4:
		var over: Rect2 = box(selected + 2)
		var w: float = font.get_string_size(UiText.text(name_key), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		draw_string(font, Vector2(over.get_center().x - w * 0.5, over.position.y - 12.0), UiText.text(name_key), HORIZONTAL_ALIGNMENT_LEFT,
			-1, size, ScreenElementRegistry.INK)


## One box: the panel, its frame (thick when selected), the item's shape and its count as pips.
func _slot(r: Rect2, item: Array, selected: bool, scale_k: float) -> void:
	draw_rect(r, ScreenElementRegistry.PANEL, true)
	draw_rect(r, ScreenElementRegistry.INK if selected else ScreenElementRegistry.DIM, false, 4.0 if selected else 2.0)
	var kind: int = _kind(item)
	if kind == ItemKinds.Kind.NONE:
		return
	EntityRenderer.draw_item(self, kind, r.get_center(), BOX * 1.9 * scale_k)
	var count: int = int(Variants.number(item[1])) if item.size() > 1 else 0
	if count > 1:
		for p: int in count:
			draw_circle(Vector2(r.position.x + 10.0 + p * 10.0, r.end.y - 9.0), 3.5, ScreenElementRegistry.INK)


static func _kind(item: Array) -> int:
	return int(Variants.number(item[0])) if not item.is_empty() else ItemKinds.Kind.NONE
