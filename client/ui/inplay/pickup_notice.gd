class_name PickupNotice
extends Node2D
## A standard pick-up notice above the hotbar (the first playtest: a player could not tell what they
## had picked up or where it went): "Picked up a spanner · belt 2" for camera.pickup_notice_s. It
## reads the inventory record alone: an item kind whose count across the hands and belt grows is
## named, with where it went (the lamp hand, the free hand, or the belt slot by its key). Moving a
## thing between hands, hook and belt is no pick-up. The first record (the welcome) shows nothing.

## The name key of what was picked up, the place key, the slot's key label ("" for a hand).
var item_key: String = ""
var place_key: String = ""
var key_label: String = ""
var _until: float = -1.0
var _last: Dictionary = {}


func _init() -> void:
	ScreenElementRegistry.mark(self, &"pickup_notice")
	visible = false


## One frame: `inventory` (ClientConnection.inventory), `store`/`family` for the slot keys.
func update(shown: bool, inventory: Dictionary, store: BindingsStore, family: String, now_s: float) -> void:
	if not inventory.is_empty() and not _last.is_empty() and inventory != _last:
		var gained: Dictionary = gained_place(_last, inventory)
		if not gained.is_empty():
			item_key = ItemKinds.text_key(int(Variants.number(gained["kind"])))
			place_key = str(gained["place"])
			var slot: int = int(Variants.number(gained.get("slot", -1)))
			key_label = GlyphText.label(store, "slot_%d" % (slot + 1), family) if slot >= 0 and store != null else ""
			_until = now_s + Tuning.f(&"camera.pickup_notice_s")
	if not inventory.is_empty():
		_last = inventory.duplicate(true)
	visible = shown and now_s < _until and not UiText.text(item_key).is_empty()
	queue_redraw()


## What grew from `before` to `after`: {kind, place ("toast.lamp_hand" | "toast.free_hand" |
## "toast.belt"), slot (belt index, or -1)}, or {} when nothing new arrived.
static func gained_place(before: Dictionary, after: Dictionary) -> Dictionary:
	var had: Dictionary = counts(before)
	var has: Dictionary = counts(after)
	for raw: Variant in has.keys():
		if int(Variants.number(has[raw])) <= int(Variants.number(had.get(raw, 0))):
			continue
		var kind: int = int(Variants.number(raw))
		if _kind_of(Variants.array(after.get("lamp", []))) == kind and _kind_of(Variants.array(before.get("lamp", []))) != kind:
			return {"kind": kind, "place": "toast.lamp_hand", "slot": -1}
		if _kind_of(Variants.array(after.get("free", []))) == kind and _kind_of(Variants.array(before.get("free", []))) != kind:
			return {"kind": kind, "place": "toast.free_hand", "slot": -1}
		var was: Array = Variants.array(before.get("slots", []))
		var now: Array = Variants.array(after.get("slots", []))
		for i: int in now.size():
			var item: Array = Variants.array(now[i])
			var old: Array = Variants.array(was[i]) if i < was.size() else []
			if _kind_of(item) == kind and (_kind_of(old) != kind or _count_of(item) > _count_of(old)):
				return {"kind": kind, "place": "toast.belt", "slot": i}
		return {"kind": kind, "place": "toast.belt", "slot": -1}
	return {}


## Each kind's count across the lamp hand, the free hand and the belt.
static func counts(inventory: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var places: Array = [Variants.array(inventory.get("lamp", [])), Variants.array(inventory.get("free", []))]
	places.append_array(Variants.array(inventory.get("slots", [])))
	for raw: Variant in places:
		var item: Array = Variants.array(raw)
		var kind: int = _kind_of(item)
		if kind != ItemKinds.Kind.NONE:
			out[kind] = int(Variants.number(out.get(kind, 0))) + maxi(1, _count_of(item))
	return out


static func _kind_of(item: Array) -> int:
	return int(Variants.number(item[0])) if not item.is_empty() else ItemKinds.Kind.NONE


static func _count_of(item: Array) -> int:
	return int(Variants.number(item[1])) if item.size() > 1 else 0


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var size: int = ScreenElementRegistry.min_font_px()
	var top: float = Hotbar.origin().y - size * 2.4
	var parts_w: float = font.get_string_size(UiText.text("toast.picked_up"), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x \
		+ font.get_string_size(UiText.text(item_key), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x \
		+ font.get_string_size(UiText.text(place_key), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x \
		+ font.get_string_size(key_label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 60.0
	var x: float = (ScreenElementRegistry.CANVAS.x - parts_w) * 0.5
	draw_rect(Rect2(x - 14.0, top - size, parts_w + 28.0, size + 16.0), ScreenElementRegistry.PANEL, true)
	draw_string(font, Vector2(x, top), UiText.text("toast.picked_up"), HORIZONTAL_ALIGNMENT_LEFT, -1, size, ScreenElementRegistry.DIM)
	x += font.get_string_size(UiText.text("toast.picked_up"), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 12.0
	draw_string(font, Vector2(x, top), UiText.text(item_key), HORIZONTAL_ALIGNMENT_LEFT, -1, size, ScreenElementRegistry.INK)
	x += font.get_string_size(UiText.text(item_key), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 20.0
	draw_string(font, Vector2(x, top), UiText.text(place_key), HORIZONTAL_ALIGNMENT_LEFT, -1, size, ScreenElementRegistry.DIM)
	x += font.get_string_size(UiText.text(place_key), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 8.0
	draw_string(font, Vector2(x, top), key_label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ScreenElementRegistry.INK)
