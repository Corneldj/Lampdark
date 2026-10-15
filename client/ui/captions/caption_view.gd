class_name CaptionView
extends Control
## UI-03: the caption lines, bottom centre above the subtitles, newest lowest, in UI-01's plain ink on
## a dark panel, and each positional line's edge arc. Its content is only what CaptionSystem says
## (text from a key, a band, a voice and a bearing): never a distance, a name or a number.

const MARGIN: float = 24.0

var system: CaptionSystem = null
## UI-06's text size, 1.0 to 2.0.
var text_scale: float = 1.0
## The space the subtitles take below (SubtitleView sets it).
var bottom_offset: float = 0.0
var arcs: Array[CaptionArc] = []
var _shown: Array[Dictionary] = []


func _init() -> void:
	ScreenElementRegistry.mark(self, &"caption")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func font_px() -> int:
	return roundi(ScreenElementRegistry.min_font_px() * clampf(text_scale, 1.0, 2.0))


func refresh(now_s: float) -> void:
	if system == null:
		return
	system.tick(now_s)
	_shown = system.visible_lines()
	var bearings: Array[float] = []
	for l: Dictionary in _shown:
		if l["bearing"] != null:
			bearings.append(float(Variants.number(l["bearing"])))
	while arcs.size() < bearings.size():
		var a: CaptionArc = CaptionArc.new()
		add_child(a)
		arcs.append(a)
	var half: Vector2 = size / 2.0 - Vector2(MARGIN, MARGIN)
	for i: int in arcs.size():
		arcs[i].show_bearing(i < bearings.size(), size / 2.0, bearings[i] if i < bearings.size() else 0.0, half)
	queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var px: int = font_px()
	var line_h: float = px * 1.35
	var y: float = size.y - MARGIN - bottom_offset
	for i: int in range(_shown.size() - 1, -1, -1):
		var text: String = str(_shown[i]["text"])
		if text.is_empty():
			continue
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var at: Vector2 = Vector2((size.x - w) / 2.0, y - line_h)
		draw_rect(Rect2(at - Vector2(10.0, 0.0), Vector2(w + 20.0, line_h)), ScreenElementRegistry.PANEL)
		draw_string(font, at + Vector2(0.0, px), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, ScreenElementRegistry.INK)
		y -= line_h
