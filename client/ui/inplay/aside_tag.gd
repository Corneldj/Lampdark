class_name AsideTag
extends Node2D
## UI-01's Aside tag (Gameplay §6.5): while the Aside is held, in streamer mode, a plain 'Aside' tag
## in the top corner, so a stream's viewers know the line was not said in the mine. SND-14 owns the
## Aside's rules. Its content is nothing but whether it shows.


func _init() -> void:
	ScreenElementRegistry.mark(self, &"aside_tag")
	visible = false
	position = Vector2(1920.0 - 40.0, 48.0)


func update(aside_held: bool, streamer_mode: bool) -> void:
	visible = aside_held and streamer_mode
	queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var size: int = ScreenElementRegistry.min_font_px() + 4
	var text: String = UiText.text("ui.aside")
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 28.0
	var box: Rect2 = Rect2(-w, -size, w, size + 16.0)
	draw_rect(box, ScreenElementRegistry.PANEL, true)
	draw_rect(box, ScreenElementRegistry.INK, false, 2.0)
	draw_string(font, Vector2(-w + 14.0, 6.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ScreenElementRegistry.INK)
