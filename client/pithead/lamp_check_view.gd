class_name LampCheckView
extends Control
## RSC-06 (Gameplay §11.9, §6.8, GDD §14.3): Lamp Check at the pithead as the client shows it, in
## grey box. The board of hooks along the top, one per miner by lamp number, each brass check hung as
## the lampman reaches it (LampmanSequence); his lines on the Pithead bus, subtitled (UI-03); the
## band under it all, silent while he reads. Then the shareable card (LampCheckCard's text) with
## Save card (LampCheckCardImage's PNG) and, once LFT-14 has it, the map card. Friends press Ready;
## in public the pithead empties on its budget. The Inquiry cards and replays (RSC-07, RSC-08) and the
## Pocket Book lines (MOD-02) come between the reading and the card when they are built. The
## screen covers the mine and sits under the captions' layer, so his subtitles show over it.
## Driven by step(now_s), so tests run it without a clock. Client-side.

signal ready_pressed
## The card was saved as a PNG at `path` (client_main adds it to Steam's library).
signal card_saved(path: String, image: Image)

const DAWN: Color = Color(0.17, 0.19, 0.23)
const BOARD: Color = Color(0.29, 0.24, 0.19)
const BRASS: Color = Color(0.78, 0.62, 0.30)
const CHALK: Color = Color(0.86, 0.84, 0.78)
const SILENT_DB: float = -80.0

## The opening as received (LampCheckWire.read).
var opening: Dictionary = {}
var sequence: LampmanSequence = null
## (text_key, duration_s, now_s) -> void: UI-03's subtitles.
var subtitle: Callable = Callable()
## () -> Image: LFT-14's map card, null until it is ready.
var map_card: Callable = func() -> Image: return null
## Each hook's check: hung yet.
var hung: Array[bool] = []
var started_s: float = -1.0
var ready_sent: bool = false
var saved_path: String = ""
## Every line he has spoken, as [line_id, form, caption key] (tests read it).
var spoken: Array[Array] = []
var _last_t: float = 0.0
var _band: AudioStreamPlayer = null
var _voice: AudioStreamPlayer = null
var _board: Control = null
var _card: Label = null
var _status: Label = null
var _ready: Button = null
var _save: Button = null
var _map: TextureRect = null


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


## Shows Lamp Check from its opening at `now_s`.
func open(o: Dictionary, now_s: float) -> void:
	opening = o
	var hooks: Array = Variants.array(o.get("hooks", []))
	sequence = LampmanSequence.build(hooks, str(o.get("remark", "")), length_of)
	hung.clear()
	for _i: int in hooks.size():
		hung.append(false)
	started_s = now_s
	_last_t = 0.0
	_build()
	_band = AudioStreamPlayer.new()
	_band.stream = SampleBank.band()
	_band.bus = "Pithead"
	_band.volume_db = Tuning.f(&"rescue.lamp_check_band_db")
	add_child(_band)
	_voice = AudioStreamPlayer.new()
	_voice.bus = "Pithead"
	add_child(_voice)
	if is_inside_tree():
		_band.play()


## A clip's length (s), from LampmanBank's stream; 0 if it is missing.
static func length_of(line_id: String, form: String) -> float:
	var s: AudioStream = LampmanBank.stream(line_id, form)
	return s.get_length() if s != null else 0.0


## Advances the reading to `now_s`: hangs checks, speaks and subtitles his lines, keeps the band
## silent while he reads, then shows the card.
func step(now_s: float) -> void:
	if sequence == null:
		return
	var t: float = now_s - started_s
	for s: LampmanSequence.Step in sequence.starting(_last_t, t + 1e-6):
		_play(s, now_s)
	_last_t = t + 1e-6
	if _band != null:
		_band.volume_db = SILENT_DB if sequence.reading(t) else Tuning.f(&"rescue.lamp_check_band_db")
	var card_shown: bool = t >= sequence.reading_to_s
	if card_shown and not _card.visible and is_inside_tree():
		# The Deck: the D-pad and A drive it, Ready (or Save card in public) focused first.
		(_ready if is_friends() and not ready_sent else _save).call_deferred("grab_focus")
	_card.visible = card_shown
	_save.visible = card_shown
	_ready.visible = card_shown and is_friends() and not ready_sent
	var card_image: Image = map_card.call() if map_card.is_valid() else null
	if card_shown and card_image != null and _map.texture == null:
		_map.texture = ImageTexture.create_from_image(card_image)
	_map.visible = card_shown and _map.texture != null
	_status.text = _status_text(t)


## Whether the band plays now (false while he reads).
func band_audible() -> bool:
	return _band != null and _band.volume_db > SILENT_DB


func is_friends() -> bool:
	return Variants.number(opening.get("public_s", 0.0)) <= 0.0


func card_text() -> String:
	return str(opening.get("card", ""))


func press_ready() -> void:
	if ready_sent or not is_friends():
		return
	ready_sent = true
	_ready.visible = false
	ready_pressed.emit()


## Writes the card as a PNG at rescue.lamp_check_card_px (card_saved tells the caller); its path, or "".
func save_card() -> String:
	var px: Array[int] = Tuning.list_i(&"rescue.lamp_check_card_px")
	if px.size() < 2:
		return ""
	var image: Image = LampCheckCardImage.render(card_text(), Vector2i(px[0], px[1]))
	saved_path = LampCheckCardImage.save(image, str(opening.get("run_uuid", "")))
	if not saved_path.is_empty():
		card_saved.emit(saved_path, image)
	return saved_path


func _play(s: LampmanSequence.Step, now_s: float) -> void:
	match s.kind:
		"hang":
			if s.hook >= 0 and s.hook < hung.size():
				hung[s.hook] = true
				_board.queue_redraw()
		"digit", "remark":
			spoken.append([s.line_id, s.form, s.key])
			var clip: AudioStream = LampmanBank.stream(s.line_id, s.form)
			if clip != null and _voice != null and _voice.is_inside_tree():
				_voice.stream = clip
				_voice.play()
			if subtitle.is_valid():
				subtitle.call(s.key, s.length_s, now_s)


func _status_text(t: float) -> String:
	if is_friends():
		return LampCheckCard.word("lamp_check.waiting") if ready_sent else ""
	var left: int = maxi(0, ceili(Variants.number(opening.get("public_s", 0.0)) - t))
	return LampCheckCard.word("lamp_check.closing").format({"s": left})


func _build() -> void:
	for child: Node in get_children():
		child.queue_free()
	var bg: ColorRect = ColorRect.new()
	bg.color = DAWN
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var column: VBoxContainer = VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 48
	column.offset_right = -48
	column.offset_top = 32
	column.offset_bottom = -32
	column.add_theme_constant_override("separation", 18)
	add_child(column)
	var title: Label = Label.new()
	title.text = LampCheckCard.word("lamp_check.title")
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", CHALK)
	column.add_child(title)
	var board: Board = Board.new()
	board.view = self
	board.custom_minimum_size = Vector2(0, 150)
	column.add_child(board)
	_board = board
	_card = Label.new()
	_card.text = card_text()
	_card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card.add_theme_font_size_override("font_size", 28)
	_card.add_theme_color_override("font_color", CHALK)
	_card.visible = false
	column.add_child(_card)
	_map = TextureRect.new()
	_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_map.custom_minimum_size = Vector2(0, 220)
	_map.visible = false
	column.add_child(_map)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	column.add_child(row)
	_save = Button.new()
	_save.name = "SaveCard"
	_save.text = LampCheckCard.word("lamp_check.save_card")
	_save.custom_minimum_size = Vector2(240, 56)
	_save.visible = false
	_save.pressed.connect(func() -> void:
		if not save_card().is_empty():
			_save.text = LampCheckCard.word("lamp_check.saved"))
	row.add_child(_save)
	_ready = Button.new()
	_ready.name = "Ready"
	_ready.text = LampCheckCard.word("lamp_check.ready")
	_ready.custom_minimum_size = Vector2(240, 56)
	_ready.visible = false
	_ready.pressed.connect(press_ready)
	row.add_child(_ready)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 22)
	_status.add_theme_color_override("font_color", CHALK)
	row.add_child(_status)


## The board of hooks: each hook's lamp number in chalk, its brass check once hung.
class Board:
	extends Control
	var view: LampCheckView = null

	func _draw() -> void:
		if view == null:
			return
		draw_rect(Rect2(Vector2.ZERO, size), LampCheckView.BOARD)
		var hooks: Array = Variants.array(view.opening.get("hooks", []))
		if hooks.is_empty():
			return
		var step_x: float = size.x / hooks.size()
		var font: Font = ThemeDB.fallback_font
		for i: int in hooks.size():
			var cx: float = step_x * (i + 0.5)
			draw_line(Vector2(cx, 18), Vector2(cx, 40), LampCheckView.CHALK, 3.0)
			if i < view.hung.size() and view.hung[i]:
				draw_rect(Rect2(cx - 22, 42, 44, 52), LampCheckView.BRASS)
			var lamp: String = str(int(Variants.number(Variants.dict(hooks[i]).get("lamp", 0))))
			draw_string(font, Vector2(cx - 30, size.y - 14), lamp, HORIZONTAL_ALIGNMENT_CENTER, 60, 22, LampCheckView.CHALK)
