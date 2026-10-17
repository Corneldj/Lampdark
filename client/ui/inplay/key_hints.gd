class_name KeyHints
extends Node2D
## Standard contextual key hints above the hotbar (the first playtest: nothing said how to light the
## lamp or how to get free; GDD §14.4 shows each lamp key once in a first run, MOD-04, and this shows
## them whenever they apply): "Hold R · Light the lamp" with a lamp out in hand, "Q · Open the
## shutter" with it shuttered, the shutter and wick keys for a while after it is first lit, "E · Press
## in the zone" while a struggle is offered (StruggleRing draws it), "Hold E · Struggle free" under
## a timber pin (HAZ-03), and coming round "W A S D · Crawl" and "Z · Call for help". Each hint is a key label from the bindings and a text key; the
## server decides everything.

## [key label, verb key, hold seconds (0: a press), fill 0..1 or -1]
var hints: Array[Array] = []
var _lit_seen: bool = false
var _lamp_keys_until: float = -1.0
var _press_since: Dictionary = {}
var _was_down: Dictionary = {}


func _init() -> void:
	ScreenElementRegistry.mark(self, &"hint")
	visible = false


## One frame. `life`: the own block's life (StatusWire.LIFE_*); `lamp_shows`: the own light's radius is above 0.
func update(shown: bool, life: int, in_window: bool, inventory: Dictionary, lamp_shows: bool, status: Dictionary,
		router: InputRouter, store: BindingsStore, now_s: float) -> void:
	hints.clear()
	var family: String = router.family if router != null else "kbm"
	var flags: int = int(Variants.number(status.get("flags", 0)))
	var holds: int = router.record.holds if router != null else 0
	if life == StatusWire.LIFE_GRABBED and (flags & StatusWire.STRUGGLE) != 0:
		_add(store, family, "interact", "hint.struggle", 0.0, -1.0)
	elif life == StatusWire.LIFE_UNCONSCIOUS and in_window:
		var key_label: String = " ".join(PackedStringArray([GlyphText.label(store, "move_up", family), GlyphText.label(store, "move_left", family),
			GlyphText.label(store, "move_down", family), GlyphText.label(store, "move_right", family)])) if store != null else ""
		hints.append([key_label, "hint.crawl", 0.0, -1.0])
		_add(store, family, "callout", "hint.call_help", 0.0, -1.0)
	elif life == StatusWire.LIFE_UPRIGHT or life == StatusWire.LIFE_CAUGHT:
		if life == StatusWire.LIFE_CAUGHT and (flags & StatusWire.TRAP_STRUGGLE) != 0:
			_add(store, family, "interact", "hint.struggle_free", Tuning.f(&"traps.timber_pin_struggle_s"), -1.0)
		_lamp_hints(inventory, lamp_shows, holds, store, family, now_s)
	visible = shown and not hints.is_empty()
	queue_redraw()


func _lamp_hints(inventory: Dictionary, lamp_shows: bool, holds: int, store: BindingsStore, family: String, now_s: float) -> void:
	var lamp: Array = Variants.array(inventory.get("lamp", [0, 0]))
	var kind: int = int(Variants.number(lamp[0])) if not lamp.is_empty() else ItemKinds.Kind.NONE
	if kind == ItemKinds.Kind.NONE or Variants.flag(inventory.get("hooked", false)):
		return
	if lamp_shows:
		if not _lit_seen:
			_lit_seen = true
			_lamp_keys_until = now_s + Tuning.f(&"camera.lamp_hint_s")
		if now_s < _lamp_keys_until:
			_add(store, family, "shutter", "hint.shutter", 0.0, -1.0)
			_add(store, family, "wick_up", "hint.wick", 0.0, -1.0)
		return
	if kind == ItemKinds.Kind.ELECTRIC_LAMP:
		_add(store, family, "shutter", "hint.switch_on", 0.0, -1.0)
	elif Variants.flag(inventory.get("lamp_shut", false)):
		_add(store, family, "shutter", "hint.open_shutter", 0.0, -1.0)
	else:
		_add(store, family, "relight", "hint.light", Tuning.f(&"lamp.flint_time"),
			_fill(&"relight", (holds & InputRecord.HOLD_RELIGHT) != 0, Tuning.f(&"lamp.flint_time"), now_s))


func _add(store: BindingsStore, family: String, action: String, verb_key: String, hold_s: float, fill: float) -> void:
	hints.append([GlyphText.label(store, action, family) if store != null else "", verb_key, hold_s, fill])


## A held hint's fill: from a fresh press of its key (as the server needs), over `hold_s`.
func _fill(action: StringName, down: bool, hold_s: float, now_s: float) -> float:
	var was: bool = Variants.flag(_was_down.get(action, false))
	_was_down[action] = down
	if not down:
		_press_since.erase(action)
		return 0.0
	if not was:
		_press_since[action] = now_s
	if not _press_since.has(action):
		return 0.0
	return clampf((now_s - float(Variants.number(_press_since[action]))) / maxf(hold_s, 0.001), 0.0, 1.0)


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var size: int = ScreenElementRegistry.min_font_px()
	var widths: Array[float] = []
	var total: float = 0.0
	for h: Array in hints:
		var key_label: String = h[0]
		var hold_s: float = h[2]
		var key_text_w: float = font.get_string_size(key_label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var hold_w: float = font.get_string_size(UiText.text("glyph.hold"), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 10.0 if hold_s > 0.0 else 0.0
		var w: float = hold_w + maxf(36.0, key_text_w + 16.0) + 10.0 + font.get_string_size(UiText.text(str(h[1])), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		widths.append(w)
		total += w + 40.0
	var x: float = (ScreenElementRegistry.CANVAS.x - total + 40.0) * 0.5
	var y: float = Hotbar.origin().y - 26.0
	for i: int in hints.size():
		var h: Array = hints[i]
		var key_label: String = h[0]
		var hold_s: float = h[2]
		var fill: float = h[3]
		draw_rect(Rect2(x - 12.0, y - size - 6.0, widths[i] + 24.0, size + 16.0), ScreenElementRegistry.PANEL, true)
		var cx: float = x
		if hold_s > 0.0:
			draw_string(font, Vector2(cx, y), UiText.text("glyph.hold"), HORIZONTAL_ALIGNMENT_LEFT, -1, size, ScreenElementRegistry.DIM)
			cx += font.get_string_size(UiText.text("glyph.hold"), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 10.0
		var key_w: float = maxf(36.0, font.get_string_size(key_label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 16.0)
		var box: Rect2 = Rect2(cx, y - size, key_w, size + 8.0)
		draw_rect(box, ScreenElementRegistry.INK, false, 2.0)
		draw_string(font, Vector2(cx + 8.0, y), key_label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ScreenElementRegistry.INK)
		draw_string(font, Vector2(cx + key_w + 10.0, y), UiText.text(str(h[1])), HORIZONTAL_ALIGNMENT_LEFT, -1, size, ScreenElementRegistry.INK)
		if hold_s > 0.0 and fill > 0.0:
			var c: Vector2 = Vector2(x - 26.0, y - size * 0.35)
			draw_arc(c, 10.0, 0.0, TAU, 24, ScreenElementRegistry.PANEL, 5.0, true)
			draw_arc(c, 10.0, -PI * 0.5, -PI * 0.5 + TAU * fill, 24, ScreenElementRegistry.INK, 4.0, true)
		x += widths[i] + 40.0
