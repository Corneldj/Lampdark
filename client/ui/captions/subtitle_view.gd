class_name SubtitleView
extends Control
## UI-03: recorded speech subtitled (the lampman, the cold open's recordings, the roll call's
## character line), at the very bottom, on by default and shown with captions off.

const MARGIN: float = 24.0

var system: CaptionSystem = null
var text_scale: float = 1.0
var _shown: Array[String] = []


func _init() -> void:
	ScreenElementRegistry.mark(self, &"caption")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func font_px() -> int:
	return roundi(ScreenElementRegistry.min_font_px() * clampf(text_scale, 1.0, 2.0))


## The height the subtitles take now (CaptionView sits above it).
func used_height() -> float:
	return 0.0 if _shown.is_empty() else _shown.size() * font_px() * 1.35 + MARGIN


func refresh(now_s: float) -> void:
	if system == null:
		return
	system.tick(now_s)
	_shown = system.visible_subtitles()
	queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var px: int = font_px()
	var line_h: float = px * 1.35
	var y: float = size.y - MARGIN
	for i: int in range(_shown.size() - 1, -1, -1):
		var w: float = font.get_string_size(_shown[i], HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var at: Vector2 = Vector2((size.x - w) / 2.0, y - line_h)
		draw_rect(Rect2(at - Vector2(10.0, 0.0), Vector2(w + 20.0, line_h)), ScreenElementRegistry.PANEL)
		draw_string(font, at + Vector2(0.0, px), _shown[i], HORIZONTAL_ALIGNMENT_LEFT, -1, px, ScreenElementRegistry.FLAME)
		y -= line_h
