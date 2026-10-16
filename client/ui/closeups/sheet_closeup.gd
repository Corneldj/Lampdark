class_name SheetCloseup
extends CloseupBase
## LFT-14 and LFT-03: the close-up of one of the crew's sheets (SheetKind): the map table's survey
## sheet, the Manual's page. It shows this client's copy of the sheet (ClientSheet) only while open:
## every stroke and label, unsigned, this miner's own commits at once, and the others' strokes as
## they are made. Pencil, rubber and typed labels through SheetPencil; pan and zoom (Proposed: WASD
## or middle-drag and the wheel; the left stick and the D-pad; pinch on a touchscreen). A subclass
## draws what is printed under the pencil (_draw_paper) and sets the view (on_open, view_limits,
## clamp_view).
##
## - Pads: the right stick moves the pencil's cursor, slowed by mine.pencil_slow_cursor_scale while
##   the slow cursor is on (the default with a pad); RT draws, LT rubs, A types a label with Steam's
##   floating keyboard (Godot's own without Steam).
## - Touch is the pencil (contact is pencil-down); the Deck's trackpad arrives as the mouse.
## - Lines are at least mine.pencil_min_px wide at 1x, 1x-2x by the line-weight option; labels in
##   the pencil hand or plain type, each through STM-08's filter when it carries an author.
## - It never draws, snaps or shows anything the sheet does not hold, and nothing of it leaves
##   this close-up.

## The first-use glyphs MOD-04 asks for, once each, in a New Brigade miner's first run.
signal first_use(tool: StringName)

const PENCIL_GREY: Color = Color(0.25, 0.25, 0.26)
const PRINT_INK: Color = Color(0.16, 0.14, 0.12)

## The client's sheet, as the connection holds it now: () -> ClientSheet.
var client_sheet: Callable = Callable()
## MNR-15's bindings and router (the device family), for the pencil and rubber buttons and glyphs.
var store: BindingsStore = null
var router: InputRouter = null
## The pad's state this frame: () -> {pencil, rubber, stick_r: Vector2, stick_l: Vector2,
## zoom_in, zoom_out} (GodotInputSource.close_up_pad; STM-06's Steam Input fills the same).
var pad_state: Callable = Callable()
## Steam's floating keyboard over a field: (Rect2i) -> bool; false or unset uses Godot's own.
var show_keyboard: Callable = Callable()
## UI-06's options: line weight (1-2), plain type for labels, the straight-line aid, the slow
## cursor (on by default with a pad) and contrast (Brightness and Lamp Glow raise it).
var line_weight: float = 1.0
var plain_type: bool = false
var slow_cursor: bool = true
var contrast: float = 1.0
## MOD-04: true in a New Brigade miner's first run (each tool's glyph shows once, when needed).
var teach: bool = false
## The view: the sheet point at the screen's centre and the sheet units across its short side.
var centre: Vector2 = Vector2.ZERO
var view_units: float = 3072.0
## The pencil's cursor on screen (the mouse's, or the pad's own).
var cursor: Vector2 = Vector2.ZERO
var pencil: SheetPencil = SheetPencil.new()
var label_field: LineEdit = null
var _cs: ClientSheet = null
var _canvas: Node2D = null
var _overlay: Control = null
## bucket -> its node.
var _buckets: Dictionary = {}
var _width_units: float = -1.0
var _panning: bool = false
var _pad_down: Dictionary = {}
var _touches: Dictionary = {}
var _pinch_from: float = 0.0
var _taught: Dictionary = {}


## One bucket of committed strokes, drawn in sheet units and redrawn only when it changes. A
## stroke is drawn by the bucket of its first point, so none is drawn twice.
class Bucket:
	extends Node2D
	var sheet: Sheet = null
	var bucket: Vector2i = Vector2i.ZERO
	var width_units: float = 10.0
	var colour: Color = PENCIL_GREY

	func _draw() -> void:
		for id: int in sheet.ids_in_bucket(bucket):
			if not sheet.strokes.has(id):
				continue
			var s: SheetStroke = sheet.strokes[id]
			if Sheet.bucket_of(s.points[0]) != bucket:
				continue
			if s.points.size() == 1:
				draw_circle(s.points[0], width_units * 0.5, colour)
			else:
				draw_polyline(s.points, colour, width_units, true)


## The layer over the strokes: labels, strokes being made, the cursor (redrawn each frame).
class Overlay:
	extends Control
	var view: SheetCloseup = null

	func _draw() -> void:
		view.draw_overlay(self)


func _init() -> void:
	super._init()
	_canvas = Node2D.new()
	_canvas.name = "Strokes"
	add_child(_canvas)
	var overlay: Overlay = Overlay.new()
	overlay.name = "Overlay"
	overlay.view = self
	_overlay = overlay
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	label_field = LineEdit.new()
	label_field.name = "LabelField"
	label_field.visible = false
	label_field.max_length = 0
	label_field.custom_minimum_size = Vector2(320, 0)
	label_field.text_changed.connect(_on_label_changed)
	label_field.text_submitted.connect(_on_label_submitted)
	add_child(label_field)


func on_open(_context: Dictionary) -> void:
	cursor = size * 0.5
	_refresh(true)


func on_close() -> void:
	pencil.cancel()
	_hide_label()
	_panning = false
	_touches.clear()


## The router's presses (20 Hz): the label key.
func handle(action: String) -> bool:
	if action == "label":
		if not label_field.visible:
			_show_label()
		return true
	return false


## Esc or B while a label is being typed backs out of it; otherwise the table closes.
func back_out() -> bool:
	if label_field.visible:
		_hide_label()
		return true
	return false


#region View

## Pixels a sheet unit.
func zoom() -> float:
	return maxf(1.0, minf(size.x, size.y)) / maxf(1.0, view_units)


func to_screen(p: Vector2) -> Vector2:
	return size * 0.5 + (p - centre) * zoom()


func to_sheet(at: Vector2) -> Vector2:
	return centre + (at - size * 0.5) / zoom()


## The sheet's rectangle on screen now.
func visible_rect() -> Rect2:
	var a: Vector2 = to_sheet(Vector2.ZERO)
	var b: Vector2 = to_sheet(size)
	return Rect2(a, b - a)


## Zooms by `factor` (above 1 zooms in), keeping the sheet point under `at` still.
func zoom_by(factor: float, at: Vector2) -> void:
	var before: Vector2 = to_sheet(at)
	var span: Vector2 = view_limits()
	view_units = clampf(view_units / factor, span.x, span.y)
	centre += before - to_sheet(at)
	clamp_view()


func pan(pixels: Vector2) -> void:
	centre += pixels / zoom()
	clamp_view()


## The closest and the farthest view, in sheet units across the short side (a subclass's).
func view_limits() -> Vector2:
	return Vector2(512.0, float(SheetStroke.MAX - SheetStroke.MIN))


## Keeps the view on the sheet (a subclass may hold it to its page).
func clamp_view() -> void:
	centre = centre.clamp(Vector2(SheetStroke.MIN, SheetStroke.MIN), Vector2(SheetStroke.MAX, SheetStroke.MAX))

#endregion

#region Input

func _gui_input(event: InputEvent) -> void:
	# Touch is handled as touch; the mouse it also emulates is ignored.
	if event.device == InputEvent.DEVICE_ID_EMULATION and (event is InputEventMouse):
		return
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		cursor = motion.position
		if _panning:
			pan(-motion.relative)
		elif pencil.tool != SheetPencil.Tool.NONE:
			pencil.drag(to_sheet(cursor), Transport.now_usec())
		accept_event()
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		cursor = button.position
		_mouse_button(button)
		accept_event()
	elif event is InputEventScreenTouch:
		_touch(event as InputEventScreenTouch)
		accept_event()
	elif event is InputEventScreenDrag:
		_touch_drag(event as InputEventScreenDrag)
		accept_event()
	elif event is InputEventMagnifyGesture:
		var g: InputEventMagnifyGesture = event
		zoom_by(g.factor, g.position)
		accept_event()


func _mouse_button(button: InputEventMouseButton) -> void:
	var actions: Array[String] = store.action_for(button, "kbm") if store != null else []
	var now: int = Transport.now_usec()
	if button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if button.pressed:
			var by: float = Tuning.f(&"mine.sheet_zoom_step")
			zoom_by(by if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / by, button.position)
		return
	if button.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = button.pressed
		return
	var which: SheetPencil.Tool = SheetPencil.Tool.NONE
	if actions.has("pencil"):
		which = SheetPencil.Tool.PENCIL
	elif actions.has("rubber"):
		which = SheetPencil.Tool.RUBBER
	if which == SheetPencil.Tool.NONE or label_field.visible:
		return
	if button.pressed:
		_press(which, now)
	elif pencil.tool == which:
		pencil.release(to_sheet(cursor), now)


func _touch(t: InputEventScreenTouch) -> void:
	var now: int = Transport.now_usec()
	if t.pressed:
		_touches[t.index] = t.position
	else:
		_touches.erase(t.index)
	if _touches.size() >= 2:
		# A second finger: a pinch, never a line.
		if pencil.tool != SheetPencil.Tool.NONE:
			pencil.cancel()
		_pinch_from = _pinch_span()
		return
	if t.index != 0:
		return
	cursor = t.position
	if t.pressed and not label_field.visible:
		_press(SheetPencil.Tool.PENCIL, now)
	elif not t.pressed and pencil.tool == SheetPencil.Tool.PENCIL:
		pencil.release(to_sheet(cursor), now)


func _touch_drag(d: InputEventScreenDrag) -> void:
	_touches[d.index] = d.position
	if _touches.size() >= 2:
		var span: float = _pinch_span()
		if _pinch_from > 0.0 and span > 0.0:
			zoom_by(span / _pinch_from, _pinch_centre())
		_pinch_from = span
		return
	if d.index == 0:
		cursor = d.position
		if pencil.tool != SheetPencil.Tool.NONE:
			pencil.drag(to_sheet(cursor), Transport.now_usec())


func _pinch_span() -> float:
	var pts: Array = _touches.values()
	if pts.size() < 2:
		return 0.0
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	return a.distance_to(b)


func _pinch_centre() -> Vector2:
	var pts: Array = _touches.values()
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	return (a + b) * 0.5


func _press(which: SheetPencil.Tool, now: int) -> void:
	pencil.press(which, to_sheet(cursor), now)
	_note_use(&"pencil" if which == SheetPencil.Tool.PENCIL else &"rubber")


## Each frame while open: the pad's cursor, triggers, pan and zoom; WASD pan; the view.
func step(delta: float) -> void:
	if not visible:
		return
	_refresh(false)
	if not label_field.visible:
		_keys_pan(delta)
		_pad(delta)
	if pencil.tool != SheetPencil.Tool.NONE and pencil.straight_lines:
		pencil.drag(to_sheet(cursor), Transport.now_usec())
	_overlay.queue_redraw()


func _process(delta: float) -> void:
	step(delta)


func _keys_pan(delta: float) -> void:
	var dir: Vector2 = Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		dir.x += 1.0
	if dir != Vector2.ZERO:
		pan(dir.normalized() * Tuning.f(&"mine.sheet_pan_px_s") * _px_scale() * delta)


## The pad: right stick the cursor (slowed while the slow cursor is on), RT the pencil, LT the
## rubber, left stick pan, D-pad up and down zoom.
func _pad(delta: float) -> void:
	if not pad_state.is_valid() or router == null or router.family != "pad":
		return
	var p: Dictionary = Variants.dict(pad_state.call())
	var dead: float = Tuning.f(&"movement.stick_dead_zone")
	var stick_r: Vector2 = p.get("stick_r", Vector2.ZERO)
	if stick_r.length() > dead:
		var speed: float = Tuning.f(&"mine.pencil_cursor_px_s") * _px_scale()
		if slow_cursor:
			speed *= Tuning.f(&"mine.pencil_slow_cursor_scale")
		cursor = (cursor + stick_r * speed * delta).clamp(Vector2.ZERO, size)
		if pencil.tool != SheetPencil.Tool.NONE:
			pencil.drag(to_sheet(cursor), Transport.now_usec())
	var stick_l: Vector2 = p.get("stick_l", Vector2.ZERO)
	if stick_l.length() > dead:
		pan(stick_l * Tuning.f(&"mine.sheet_pan_px_s") * _px_scale() * delta)
	for button: String in ["pencil", "rubber"]:
		var down: bool = Variants.flag(p.get(button, false))
		var was: bool = Variants.flag(_pad_down.get(button, false))
		_pad_down[button] = down
		var which: SheetPencil.Tool = SheetPencil.Tool.PENCIL if button == "pencil" else SheetPencil.Tool.RUBBER
		if down and not was:
			_press(which, Transport.now_usec())
		elif was and not down and pencil.tool == which:
			pencil.release(to_sheet(cursor), Transport.now_usec())
	for button: String in ["zoom_in", "zoom_out"]:
		var down: bool = Variants.flag(p.get(button, false))
		if down and not Variants.flag(_pad_down.get(button, false)):
			var step_by: float = Tuning.f(&"mine.sheet_zoom_step")
			zoom_by(step_by if button == "zoom_in" else 1.0 / step_by, cursor)
		_pad_down[button] = down


## Speeds are in 1080p pixels.
func _px_scale() -> float:
	return maxf(1.0, size.y) / 1080.0

#endregion

#region Labels

func _show_label() -> void:
	if _cs == null or _cs.full:
		return
	pencil.at = SheetOps.on_sheet(to_sheet(cursor))
	label_field.text = ""
	label_field.position = (cursor - Vector2(0, label_field.size.y * 0.5)).clamp(Vector2.ZERO, size - label_field.size)
	label_field.visible = true
	label_field.grab_focus()
	_note_use(&"label")
	var field: Rect2i = Rect2i(Vector2i(label_field.global_position), Vector2i(label_field.size))
	if router != null and router.family == "pad" and show_keyboard.is_valid():
		show_keyboard.call(field)


func _hide_label() -> void:
	label_field.visible = false
	label_field.release_focus()


## The field stops at the cap: mine.sheet_label_max_chars characters and their bytes.
func _on_label_changed(text: String) -> void:
	var clipped: String = SheetOps.clip_label(text, Tuning.i(&"mine.sheet_label_max_chars"))
	if clipped != text:
		var caret: int = mini(label_field.caret_column, clipped.length())
		label_field.text = clipped
		label_field.caret_column = caret


func _on_label_submitted(text: String) -> void:
	if not text.strip_edges().is_empty():
		pencil.label(text, Transport.now_usec())
	_hide_label()

#endregion

#region Drawing

## Follows the connection's sheet: buckets that changed are redrawn, and all of them when the
## pencil's width on the paper changes with the zoom or the weight.
func _refresh(force: bool) -> void:
	var cs: ClientSheet = client_sheet.call() if client_sheet.is_valid() else null
	if cs != _cs:
		_cs = cs
		pencil.sheet = cs
		for raw: Variant in _buckets.keys():
			var gone: Node2D = _buckets[raw]
			gone.queue_free()
		_buckets.clear()
		force = true
	if _cs == null:
		return
	var z: float = zoom()
	_canvas.position = size * 0.5 - centre * z
	_canvas.scale = Vector2(z, z)
	var width: float = maxf(Tuning.f(&"mine.pencil_width_units"), Tuning.f(&"mine.pencil_min_px") / z) * line_weight
	var rewidth: bool = force or absf(width - _width_units) > _width_units * 0.15
	if rewidth:
		_width_units = width
	var dirty: Array = _cs.sheet.take_dirty()
	if force:
		dirty = _cs.sheet.buckets()
	for raw: Variant in dirty:
		_bucket(raw)
	if rewidth:
		for raw: Variant in _buckets.keys():
			var b: Bucket = _buckets[raw]
			b.width_units = _width_units
			b.colour = _pencil_colour()
			b.queue_redraw()


func _bucket(raw: Variant) -> void:
	var at: Vector2i = raw
	var b: Bucket = _buckets.get(at, null)
	if _cs.sheet.ids_in_bucket(at).is_empty():
		if b != null:
			b.queue_free()
			_buckets.erase(at)
		return
	if b == null:
		b = Bucket.new()
		b.sheet = _cs.sheet
		b.bucket = at
		b.width_units = _width_units
		b.colour = _pencil_colour()
		_canvas.add_child(b)
		_buckets[at] = b
	b.queue_redraw()


func _pencil_colour() -> Color:
	return PENCIL_GREY.darkened(clampf(contrast - 1.0, 0.0, 1.0) * 0.6)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	_draw_paper()


## What is printed under the pencil, drawn over the paper (the subclass's).
func _draw_paper() -> void:
	pass


## Labels, this miner's own strokes awaiting the server, the others' strokes as they are made,
## the straight line's preview, the cursor and the first-use glyphs.
func draw_overlay(ci: CanvasItem) -> void:
	if _cs == null:
		return
	var colour: Color = _pencil_colour()
	var px_width: float = _width_units * zoom()
	var font: Font = ThemeDB.fallback_font
	var font_px: int = roundi(Tuning.f(&"mine.sheet_label_height_units") * zoom() * 0.7)
	if font_px >= 6:
		for id: int in _cs.sheet.ids_near(visible_rect()):
			if _cs.sheet.labels.has(id):
				var l: SheetLabel = _cs.sheet.labels[id]
				var at: Vector2 = to_screen(l.anchor) + Vector2(0, font_px * 0.35)
				ci.draw_string(font, at, _cs.shown_text(l), HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, colour)
	for raw: Variant in _cs.pending.values():
		var mine: Dictionary = raw
		if mine.has("points"):
			var pts: PackedVector2Array = mine["points"]
			_polyline(ci, pts, colour, px_width)
		elif font_px >= 6:
			var anchor: Vector2 = mine["anchor"]
			ci.draw_string(font, to_screen(anchor) + Vector2(0, font_px * 0.35), str(mine["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_px, colour)
	for raw: Variant in _cs.pens.values():
		var p: Dictionary = raw
		var pts: PackedVector2Array = p["points"]
		_polyline(ci, pts, colour, px_width)
	if pencil.tool == SheetPencil.Tool.PENCIL:
		if pencil.straight_lines:
			ci.draw_line(to_screen(pencil.line_from), to_screen(pencil.line_to), colour, px_width, true)
		else:
			_polyline(ci, pencil.points, colour, px_width)
	if pencil.tool == SheetPencil.Tool.RUBBER or (router != null and router.family == "pad"):
		var r: float = Tuning.f(&"mine.sheet_rubber_radius_units") * zoom() if pencil.tool == SheetPencil.Tool.RUBBER else 4.0
		ci.draw_arc(cursor, maxf(r, 3.0), 0.0, TAU, 32, PRINT_INK, 1.5, true)
	if teach:
		_draw_glyphs(ci, font)


func _polyline(ci: CanvasItem, pts: PackedVector2Array, colour: Color, width: float) -> void:
	if pts.is_empty():
		return
	if pts.size() == 1:
		ci.draw_circle(to_screen(pts[0]), width * 0.5, colour)
		return
	var on_screen: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in pts:
		on_screen.append(to_screen(p))
	ci.draw_polyline(on_screen, colour, width, true)


## MOD-04: in a New Brigade miner's first run, each tool's glyph once, until the tool is used.
func _draw_glyphs(ci: CanvasItem, font: Font) -> void:
	var family: String = router.family if router != null else "kbm"
	var rows: Array[String] = []
	for tool_name: String in ["pencil", "rubber", "label"]:
		if _taught.has(StringName(tool_name)):
			continue
		var key: String = GlyphText.label(store, tool_name, family) if store != null else ""
		rows.append("%s · %s" % [key, UiText.text("sheet." + tool_name)])
	var y: float = size.y - 24.0
	for row: String in rows:
		ci.draw_string(font, Vector2(24.0, y), row, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, PRINT_INK)
		y -= 30.0


func _note_use(tool_name: StringName) -> void:
	if not _taught.has(tool_name):
		_taught[tool_name] = true
		first_use.emit(tool_name)

#endregion
