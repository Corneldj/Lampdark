class_name QaOverlayTags
extends CanvasLayer
## FND-08 (GDD §15.7): the QA overlay. A debug-lane tag names an illusion this client received, by
## frame tick and record number; this client alone draws that event's caption and arc tag in magenta
## (reserved for this overlay, VIS-06) with its lie-log id. Tags arrive only on QA and dev servers,
## and only while the overlay is on. The normal stream is untouched: the tag finds its event among
## those already received.

const SHOW_S: float = 4.0

## {number, illusion_id, type, direction, shown_s}, one per tag drawn.
var tags: Array[Dictionary] = []
## Tags received (tests).
var received: int = 0
var on: bool = false
var _canvas: Control = null


func _ready() -> void:
	layer = 95
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_tags)
	add_child(_canvas)


## One tag: {tick, number, illusion_id}; `events` are the connection's received events.
func on_tag(tag: Dictionary, events: Array[Dictionary], listener: Vector2) -> void:
	received += 1
	var number: int = int(Variants.number(tag.get("number", -1)))
	for ev: Dictionary in events:
		if int(Variants.number(ev.get("number", -2))) == number:
			var apparent: Vector2 = ev.get("apparent", listener)
			tags.append({"number": number, "illusion_id": tag.get("illusion_id", -1), "type": int(Variants.number(ev.get("type", 0))),
				"direction": apparent - listener, "shown_s": 0.0})
			break
	if _canvas != null:
		_canvas.queue_redraw()


func _process(delta: float) -> void:
	var kept: Array[Dictionary] = []
	for t: Dictionary in tags:
		t["shown_s"] = float(Variants.number(t["shown_s"])) + delta
		if float(Variants.number(t["shown_s"])) < SHOW_S:
			kept.append(t)
	if kept.size() != tags.size():
		tags = kept
		if _canvas != null:
			_canvas.queue_redraw()


func _draw_tags() -> void:
	if not on:
		return
	var font: Font = ThemeDB.fallback_font
	var centre: Vector2 = _canvas.get_rect().size / 2.0
	for i: int in tags.size():
		var t: Dictionary = tags[i]
		var dir: Vector2 = Variants.dict(t).get("direction", Vector2.ZERO)
		var at: Vector2 = centre + (dir.normalized() * 220.0 if dir.length() > 0.01 else Vector2.ZERO)
		_canvas.draw_arc(at, 18.0, 0.0, TAU, 32, Palette.QA_MAGENTA, 3.0)
		var noise: NoiseTypes.Type = int(Variants.number(t["type"])) as NoiseTypes.Type
		_canvas.draw_string(font, Vector2(16, 60 + i * 20), "[illusion #%s: %s]" % [t["illusion_id"], NoiseTypes.id_of(noise)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Palette.QA_MAGENTA)
