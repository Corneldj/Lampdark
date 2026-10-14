class_name FeelGlyph
extends Node2D
## UI-01's feel glyph (Gameplay §5.5): an open hand beside the own miner with what was felt ('[a
## spanner]'), an arc toward it and its verb, for vision.feel_hold_s after each answer (VIS-07's
## FeelClient). A wall bump shows the hand and its caption only. Never at the thing. Its content is a
## caption key, a bearing step (0-15 clockwise from east, or none) and a verb key.

const STEPS: int = 16
const BESIDE: Vector2 = Vector2(70.0, -70.0)

var caption_key: String = ""
var verb_key: String = ""
## Its arc, a sibling in the layer (InPlayLayer adds it).
var arc: ArcWidget = ArcWidget.new()
var _seen_feels: int = 0
var _seen_bumps: int = 0
var _until_s: float = -1.0
var _bearing_q: int = FeelMessages.NO_BEARING


func _init() -> void:
	ScreenElementRegistry.mark(self, &"feel_glyph")
	visible = false


## Each frame: the latest answer (shown when its counter moves on), and where the own miner is drawn.
func update(feel: FeelClient, miner_px: Vector2, tile_px: float, now_s: float) -> void:
	if feel != null and feel.feels != _seen_feels:
		_seen_feels = feel.feels
		caption_key = str(feel.last_feel.get("caption_key", ""))
		verb_key = str(feel.last_feel.get("verb_key", ""))
		_bearing_q = int(Variants.number(feel.last_feel.get("bearing_q", FeelMessages.NO_BEARING)))
		_until_s = now_s + Tuning.f(&"vision.feel_hold_s")
	elif feel != null and feel.bumps != _seen_bumps:
		_seen_bumps = feel.bumps
		caption_key = str(feel.last_bump.get("caption_key", ""))
		verb_key = ""
		_bearing_q = FeelMessages.NO_BEARING
		_until_s = now_s + Tuning.f(&"vision.feel_hold_s")
	visible = now_s < _until_s and not caption_key.is_empty()
	position = miner_px + BESIDE
	var aimed: bool = visible and _bearing_q < STEPS
	arc.set_arc(aimed, miner_px, _bearing_q * 360.0 / STEPS, tile_px * 1.1)
	queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var size: int = ScreenElementRegistry.min_font_px()
	# The open hand: a palm and four fingers and a thumb.
	draw_circle(Vector2.ZERO, 12.0, ScreenElementRegistry.INK)
	for i: int in 4:
		var x: float = -9.0 + i * 6.0
		draw_line(Vector2(x, -6.0), Vector2(x, -24.0), ScreenElementRegistry.INK, 4.0, true)
	draw_line(Vector2(-10.0, 4.0), Vector2(-22.0, -6.0), ScreenElementRegistry.INK, 4.0, true)
	var caption: String = UiText.text(caption_key)
	var verb: String = UiText.text(verb_key)
	draw_string(font, Vector2(24.0, -4.0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ScreenElementRegistry.INK)
	if not verb.is_empty():
		draw_string(font, Vector2(24.0, size + 2.0), verb, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ScreenElementRegistry.DIM)
