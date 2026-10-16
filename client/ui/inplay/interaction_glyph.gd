class_name InteractionGlyph
extends Node2D
## UI-01's interaction glyph (Gameplay §14.3): the bound key and the verb, on the one thing in touch
## range the client sees with identity and can do something with (shared/interaction_verbs.gd). Never
## on a shape token: a token carries no kind. Its content is a key label and a verb key.

var key_label: String = ""
var verb_key: String = ""
## What the verb acts on, when the client knows it: an item's name key ("item.spanner"), else "".
var object_key: String = ""
## A timed action's verb reads "Hold <key>" and fills a ring while interact is held: 0..1, or -1
## for a verb that is not held.
var hold_fraction: float = -1.0


func _init() -> void:
	ScreenElementRegistry.mark(self, &"interaction_glyph")
	visible = false


## The identity record nearest the own miner within `reach` tiles that has a verb:
## {token, verb_key, position (tiles)}, or {}.
static func pick(view: ReceivedView, reach: float) -> Dictionary:
	if view == null:
		return {}
	var own: Vector2 = view.own.get("position", Vector2.ZERO)
	var best: Dictionary = {}
	var best_d: float = INF
	var tokens: Array = view.entities.keys()
	tokens.sort()
	for raw: Variant in tokens:
		var e: Dictionary = view.entities[raw]
		if int(Variants.number(e.get("level", 0))) != 2:
			continue  # fringe and margin tokens never get a glyph
		var verb: String = InteractionVerbs.for_seen(int(Variants.number(e.get("size_or_kind", 0))), int(Variants.number(e.get("cues", 0))))
		var at: Vector2 = e.get("position", Vector2.ZERO)
		var d: float = at.distance_to(own)
		if verb.is_empty() or d > reach + 1e-6 or d >= best_d:
			continue
		best_d = d
		best = {"token": int(Variants.number(raw)), "verb_key": verb, "position": at, "object_key": object_key_of(e)}
	return best


## An identity record's name key when it is an item whose kind rides in its held field ("" else).
static func object_key_of(e: Dictionary) -> String:
	if int(Variants.number(e.get("size_or_kind", 0))) != SeenKind.Kind.ITEM:
		return ""
	var kind: int = int(Variants.number(e.get("in_hand", 0))) & 0x3F
	if kind == ItemKinds.Kind.NONE:
		return ""
	var key: String = ItemKinds.text_key(kind)
	return key if not UiText.text(key).is_empty() else ""


## How long interact is held for a verb's timed action (s), or 0 when the verb is a tap (the ring).
## The server's numbers, read from the client table; only a cue, the server decides.
static func hold_seconds(verb: String) -> float:
	match verb:
		"verb.pick_up":
			return Tuning.f(&"items.pick_up_time")
		"verb.lever":
			return Tuning.f(&"basecamp.gate_lever_s")
		"verb.lift":
			return Tuning.f(&"movement.carry_lift_time")
		"verb.crank":
			return Tuning.f(&"phones.crank_s")
	return 0.0


## `held_s`: how long interact has been held on this target (0 when not held).
func show_on(target_px: Variant, key: String, verb: String, held_s: float = 0.0, object: String = "") -> void:
	visible = target_px != null and not verb.is_empty()
	if visible:
		var at: Vector2 = target_px
		position = at + Vector2(0.0, -56.0)
	var hold: float = hold_seconds(verb) if visible else 0.0
	key_label = "%s %s" % [UiText.text("glyph.hold"), key] if hold > 0.0 else key
	verb_key = verb
	object_key = object if visible else ""
	hold_fraction = clampf(held_s / hold, 0.0, 1.0) if hold > 0.0 else -1.0
	queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var size: int = ScreenElementRegistry.min_font_px() + 2
	var verb: String = UiText.text(verb_key)
	var key_w: float = maxf(36.0, font.get_string_size(key_label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 16.0)
	var verb_w: float = font.get_string_size(verb, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var object_w: float = 0.0
	if not object_key.is_empty():
		object_w = 8.0 + font.get_string_size(UiText.text(object_key), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var left: float = -(key_w + 10.0 + verb_w + object_w) * 0.5
	var box: Rect2 = Rect2(left, -size, key_w, size + 12.0)
	draw_rect(box, ScreenElementRegistry.PANEL, true)
	draw_rect(box, ScreenElementRegistry.INK, false, 2.0)
	draw_string(font, Vector2(left + 8.0, 4.0), key_label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ScreenElementRegistry.INK)
	draw_string(font, Vector2(left + key_w + 10.0, 4.0), verb, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ScreenElementRegistry.INK)
	if not object_key.is_empty():
		draw_string(font, Vector2(left + key_w + 18.0 + verb_w, 4.0), UiText.text(object_key), HORIZONTAL_ALIGNMENT_LEFT, -1, size,
			ScreenElementRegistry.INK)
	if hold_fraction > 0.0:
		# The hold's ring, filling clockwise from the top beside the key.
		var centre: Vector2 = Vector2(left - 18.0, -size * 0.5 + 6.0)
		draw_arc(centre, 11.0, 0.0, TAU, 24, ScreenElementRegistry.PANEL, 5.0, true)
		draw_arc(centre, 11.0, -PI * 0.5, -PI * 0.5 + TAU * hold_fraction, 24, ScreenElementRegistry.INK, 4.0, true)
