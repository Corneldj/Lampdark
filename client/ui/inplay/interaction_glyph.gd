class_name InteractionGlyph
extends Node2D
## UI-01's interaction glyph (Gameplay §14.3): the bound key and the verb, on the one thing in touch
## range the client sees with identity and can do something with (shared/interaction_verbs.gd). Never
## on a shape token: a token carries no kind. Its content is a key label and a verb key.

var key_label: String = ""
var verb_key: String = ""


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
		best = {"token": int(Variants.number(raw)), "verb_key": verb, "position": at}
	return best


func show_on(target_px: Variant, key: String, verb: String) -> void:
	visible = target_px != null and not verb.is_empty()
	if visible:
		var at: Vector2 = target_px
		position = at + Vector2(0.0, -56.0)
	key_label = key
	verb_key = verb
	queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var size: int = ScreenElementRegistry.min_font_px() + 2
	var verb: String = UiText.text(verb_key)
	var key_w: float = maxf(36.0, font.get_string_size(key_label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 16.0)
	var verb_w: float = font.get_string_size(verb, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var left: float = -(key_w + 10.0 + verb_w) * 0.5
	var box: Rect2 = Rect2(left, -size, key_w, size + 12.0)
	draw_rect(box, ScreenElementRegistry.PANEL, true)
	draw_rect(box, ScreenElementRegistry.INK, false, 2.0)
	draw_string(font, Vector2(left + 8.0, 4.0), key_label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ScreenElementRegistry.INK)
	draw_string(font, Vector2(left + key_w + 10.0, 4.0), verb, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ScreenElementRegistry.INK)
