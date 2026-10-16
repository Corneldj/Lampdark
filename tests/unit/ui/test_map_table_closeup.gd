extends GutTest
## LFT-14: the map table's close-up on a client (Gameplay §4.8; GDD §14.5). The mouse's left
## button draws and its right rubs, where the pointer goes on the sheet; a touchscreen is the pencil
## (contact is pencil-down) and its emulated mouse is ignored, two fingers pinch; with a pad the
## right stick moves a cursor that is slow by default, RT draws; A opens a label field (Steam's
## floating keyboard over it) that stops at 40 characters, and Esc or B backs out of it before the
## table closes; labels with an author go through STM-08's filter before they are drawn.

var sent: Array[Array] = []


func before_all() -> void:
	assert_true(Tuning.load_client())


func _sheet() -> ClientSheet:
	sent.clear()
	var cs: ClientSheet = ClientSheet.new()
	cs.send = func(lane: int, payload: PackedByteArray) -> Error:
		sent.append([lane, SheetCodec.decode(payload)])
		return OK
	return cs


func _ops(kind: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m: Array in sent:
		for d: Dictionary in Variants.array(m[1]):
			if int(Variants.number(d["op"])) == kind:
				out.append(d)
	return out


## The close-up at the Deck's 1280 x 800, opened on `cs`.
func _closeup(cs: ClientSheet, family: String = "kbm") -> MapTableCloseup:
	var m: MapTableCloseup = MapTableCloseup.new()
	m.client_sheet = func() -> ClientSheet: return cs
	m.store = BindingsStore.new()
	m.router = InputRouter.new(m.store, family)
	add_child_autofree(m)
	m.set_anchors_preset(Control.PRESET_TOP_LEFT)
	m.size = Vector2(1280, 800)
	m.visible = true
	m.on_open({"kind": CloseupKind.Kind.MAP_TABLE})
	return m


func _button(button: MouseButton, pressed: bool, at: Vector2, device: int = 0) -> InputEventMouseButton:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = at
	e.device = device
	return e


func _motion(at: Vector2, relative: Vector2 = Vector2.ZERO) -> InputEventMouseMotion:
	var e: InputEventMouseMotion = InputEventMouseMotion.new()
	e.position = at
	e.relative = relative
	return e


func test_the_mouse_draws_where_it_goes_and_rubs_with_the_right_button() -> void:
	var cs: ClientSheet = _sheet()
	var m: MapTableCloseup = _closeup(cs)
	m._gui_input(_button(MOUSE_BUTTON_LEFT, true, Vector2(640, 400)))
	for i: int in range(1, 21):
		m._gui_input(_motion(Vector2(640 + i * 10, 400 + i * 2)))
	m._gui_input(_button(MOUSE_BUTTON_LEFT, false, Vector2(840, 440)))
	cs.pump(Transport.now_usec())
	var commits: Array[Dictionary] = _ops(SheetCodec.Op.COMMIT_STROKE)
	assert_eq(commits.size(), 1)
	var pts: PackedVector2Array = commits[0]["points"]
	assert_eq(pts[0], Vector2(0, 0), "the screen's centre is the shaft when the table opens")
	assert_eq(pts[pts.size() - 1], m.to_sheet(Vector2(840, 440)).round(), "to where the button came up")
	m._gui_input(_button(MOUSE_BUTTON_RIGHT, true, Vector2(700, 400)))
	m._gui_input(_motion(Vector2(760, 400)))
	m._gui_input(_button(MOUSE_BUTTON_RIGHT, false, Vector2(760, 400)))
	assert_gt(_ops(SheetCodec.Op.RUB).size(), 0, "the right button rubs")
	assert_eq(_ops(SheetCodec.Op.COMMIT_STROKE).size(), 1, "and draws nothing")


func test_the_wheel_zooms_and_the_middle_button_pans() -> void:
	var m: MapTableCloseup = _closeup(_sheet())
	var before: float = m.zoom()
	var under: Vector2 = m.to_sheet(Vector2(900, 300))
	m._gui_input(_button(MOUSE_BUTTON_WHEEL_UP, true, Vector2(900, 300)))
	assert_gt(m.zoom(), before, "zoomed in")
	assert_true(m.to_sheet(Vector2(900, 300)).is_equal_approx(under), "about the pointer")
	m._gui_input(_button(MOUSE_BUTTON_MIDDLE, true, Vector2(640, 400)))
	var centre: Vector2 = m.centre
	m._gui_input(_motion(Vector2(540, 400), Vector2(-100, 0)))
	m._gui_input(_button(MOUSE_BUTTON_MIDDLE, false, Vector2(540, 400)))
	assert_gt(m.centre.x, centre.x, "dragging the paper left moves the view right")
	assert_eq(sent.size(), 0, "panning and zooming send nothing")


func test_touch_is_the_pencil_and_its_mouse_echo_is_ignored() -> void:
	var cs: ClientSheet = _sheet()
	var m: MapTableCloseup = _closeup(cs)
	m._gui_input(_button(MOUSE_BUTTON_LEFT, true, Vector2(640, 400), InputEvent.DEVICE_ID_EMULATION))
	m._gui_input(_button(MOUSE_BUTTON_LEFT, false, Vector2(700, 400), InputEvent.DEVICE_ID_EMULATION))
	assert_eq(_ops(SheetCodec.Op.COMMIT_STROKE).size(), 0, "the emulated mouse draws nothing")
	var down: InputEventScreenTouch = InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = Vector2(640, 400)
	m._gui_input(down)
	for i: int in range(1, 11):
		var drag: InputEventScreenDrag = InputEventScreenDrag.new()
		drag.index = 0
		drag.position = Vector2(640 + i * 12, 400)
		m._gui_input(drag)
	var up: InputEventScreenTouch = InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = Vector2(760, 400)
	m._gui_input(up)
	assert_eq(_ops(SheetCodec.Op.COMMIT_STROKE).size(), 1, "contact is pencil-down")
	# Two fingers pinch: a zoom, never a line.
	var before: float = m.zoom()
	var a: InputEventScreenTouch = InputEventScreenTouch.new()
	a.index = 0
	a.pressed = true
	a.position = Vector2(600, 400)
	m._gui_input(a)
	var b: InputEventScreenTouch = InputEventScreenTouch.new()
	b.index = 1
	b.pressed = true
	b.position = Vector2(700, 400)
	m._gui_input(b)
	var spread: InputEventScreenDrag = InputEventScreenDrag.new()
	spread.index = 1
	spread.position = Vector2(800, 400)
	m._gui_input(spread)
	assert_gt(m.zoom(), before, "spread apart, the sheet zooms in")
	a.pressed = false
	b.pressed = false
	m._gui_input(b)
	m._gui_input(a)
	assert_eq(_ops(SheetCodec.Op.COMMIT_STROKE).size(), 1, "the pinch drew nothing")


func test_a_pads_cursor_is_slow_by_default_and_rt_draws() -> void:
	var cs: ClientSheet = _sheet()
	var m: MapTableCloseup = _closeup(cs, "pad")
	var pad: Dictionary = {"stick_r": Vector2(1, 0)}
	m.pad_state = func() -> Dictionary: return pad
	assert_true(m.slow_cursor, "on by default")
	var from: Vector2 = m.cursor
	m.step(0.5)
	var full: float = Tuning.f(&"mine.pencil_cursor_px_s") * (800.0 / 1080.0) * 0.5
	assert_almost_eq(m.cursor.x - from.x, full * Tuning.f(&"mine.pencil_slow_cursor_scale"), 0.01, "slowed")
	m.slow_cursor = false
	from = m.cursor
	m.step(0.2)
	assert_almost_eq(m.cursor.x - from.x, full * 0.4, 0.01, "at full speed with the aid off")
	pad["pencil"] = true  # the lambda holds this dictionary: change it, never replace it
	pad["stick_r"] = Vector2(0, 1)
	m.step(0.1)
	m.step(0.1)
	m.step(0.1)
	pad["pencil"] = false
	pad["stick_r"] = Vector2.ZERO
	m.step(0.05)
	cs.pump(Transport.now_usec())
	assert_eq(_ops(SheetCodec.Op.COMMIT_STROKE).size(), 1, "RT drew a stroke")


func test_a_label_with_the_floating_keyboard_stops_at_40_and_b_backs_out() -> void:
	var cs: ClientSheet = _sheet()
	var m: MapTableCloseup = _closeup(cs, "pad")
	var fields: Array[Rect2i] = []
	m.show_keyboard = func(field: Rect2i) -> bool:
		fields.append(field)
		return true
	assert_true(m.handle("label"), "A opens the field")
	assert_true(m.label_field.visible)
	assert_eq(fields.size(), 1, "Steam's floating keyboard over it")
	# The floating keyboard types as key events into the focused field.
	for i: int in 55:
		var key: InputEventKey = InputEventKey.new()
		key.pressed = true
		key.keycode = KEY_Y
		key.unicode = "y".unicode_at(0)
		m.get_viewport().push_input(key)
	await wait_frames(2)  # LineEdit tells of a change at the frame's end
	assert_eq(m.label_field.text.length(), 40, "the field stops at 40")
	m.label_field.text_submitted.emit(m.label_field.text)
	var labels: Array[Dictionary] = _ops(SheetCodec.Op.COMMIT_LABEL)
	assert_eq(labels.size(), 1)
	assert_eq(str(labels[0]["text"]), "y".repeat(40))
	assert_false(m.label_field.visible)
	m.handle("label")
	assert_true(m.handle("close"), "B backs out of the label")
	assert_false(m.label_field.visible)
	assert_false(m.handle("close"), "and then closes the table (the manager's)")


func test_the_manager_lets_the_label_field_take_esc_first() -> void:
	var cs: ClientSheet = _sheet()
	var manager: CloseupManager = CloseupManager.new()
	add_child_autofree(manager)
	var m: MapTableCloseup = MapTableCloseup.new()
	m.client_sheet = func() -> ClientSheet: return cs
	manager.register(CloseupKind.Kind.MAP_TABLE, m)
	manager.apply({"kind": CloseupKind.Kind.MAP_TABLE, "seat": 0})
	var router: InputRouter = InputRouter.new()
	router.open_close_up()
	m.handle("label")
	router.close_up_events = ["close"] as Array[String]
	assert_eq(manager.process_input(router), [] as Array[int], "Esc shuts the label, not the table")
	router.close_up_events = ["close"] as Array[String]
	assert_eq(manager.process_input(router), [CloseupKind.Ask.CLOSE] as Array[int], "then the table")


func test_labels_with_an_author_are_filtered_before_they_are_drawn() -> void:
	var cs: ClientSheet = _sheet()
	var filtered: Array[String] = []
	cs.filter = func(text: String, author: String) -> String:
		filtered.append(author)
		return "*".repeat(text.length())
	var mine: SheetLabel = SheetLabel.make(1, -1, Vector2(0, 0), "rude word")
	mine.author_identity = "76561198000000001"
	cs.sheet.add_label(mine)
	cs.sheet.add_label(SheetLabel.make(2, -1, Vector2(0, 400), "pump"))
	cs.sheet.add_stroke(SheetStroke.make(3, -1, PackedVector2Array([Vector2(0, 0), Vector2(100, 0)])))
	var m: MapTableCloseup = _closeup(cs)
	m.step(0.016)
	await wait_frames(2)
	assert_gt(filtered.size(), 0, "the label was drawn through the filter")
	for author: String in filtered:
		assert_eq(author, "76561198000000001", "only the public label goes through it")
	assert_eq(cs.shown_text(mine), "*********")
	var plain: SheetLabel = cs.sheet.labels[2]
	assert_eq(cs.shown_text(plain), "pump", "a friends lobby's label as written")
