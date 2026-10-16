class_name CloseupBase
extends Control
## UI-02: the base every close-up's content extends (LFT-14's map table, LFT-15's Pocket Book,
## LFT-03's Manual, LFT-13's board). It fills the screen and is opaque: nothing of the mine shows
## through it. CloseupManager calls on_open() and on_close(), and routes each close-up action
## (InputContexts.CLOSE_UP_ACTIONS) to handle(). Content asks to close with request_close(). What a
## close-up shows stays here, on this screen: never in the world view, a frame or anyone's watch.
## Until a content ticket lands, a kind shows this placeholder: paper, a brass frame and its title.

signal close_requested

const PAPER: Color = Color(0.86, 0.82, 0.71)
const BRASS: Color = Color(0.55, 0.43, 0.2)
const PRINT: Color = Color(0.16, 0.14, 0.12)

var kind: CloseupKind.Kind = CloseupKind.Kind.NONE


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


## The close-up opened; `context`: {kind}.
func on_open(_context: Dictionary) -> void:
	pass


func on_close() -> void:
	pass


## One close-up action this frame; true when the content used it. "close" (Esc or B) comes here
## first: true backs out of the content's own step (a label being typed) instead of closing.
func handle(_action: String) -> bool:
	return false


func request_close() -> void:
	close_requested.emit()


func _draw() -> void:
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(r, PAPER)
	var edge: float = maxf(8.0, minf(size.x, size.y) * 0.02)
	draw_rect(r.grow(-edge * 0.5), BRASS, false, edge)
	var title: String = UiText.text("closeup." + CloseupKind.name_of(kind))
	if title.is_empty():
		return
	var font: Font = ThemeDB.fallback_font
	var font_size: int = maxi(24, roundi(minf(size.x, size.y) * 0.05))
	var w: float = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2((size.x - w) * 0.5, edge * 3.0 + font_size), title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, PRINT)
