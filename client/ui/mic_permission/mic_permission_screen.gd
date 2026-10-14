class_name MicPermissionScreen
extends Control
## SND-10: the microphone permission screen (GDD §14.4, §15.6). Plain text on what the microphone
## is for, then two equal choices, **Use my microphone** and **Mute (callouts and taps only)**: the
## same size, font and colour, neither selected or focused when the screen opens. The first left or
## right input (stick, D-pad or keys) focuses that side's button and A or Enter confirms it; a mouse
## click chooses directly. A link opens the full notice, scrollable. Sizes are for the 1080p base:
## at the Deck's 1280x800 body text draws at about 17 px.
## Placeholder art; UI-07 dresses it and localises the text.

signal chosen(mode: int)

var mic_mode: MicMode = null
var use_button: Button = null
var mute_button: Button = null
var notice_link: LinkButton = null
var notice_panel: Control = null
var _text: Dictionary = {}


func _init(mode: MicMode = null) -> void:
	mic_mode = mode


func _ready() -> void:
	_text = MicMode.notice("en")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var centre: CenterContainer = CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size = Vector2(980, 0)
	column.add_theme_constant_override("separation", 22)
	centre.add_child(column)
	var title: Label = Label.new()
	title.text = str(_text.get("title", ""))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	column.add_child(title)
	for line: Variant in Variants.array(_text.get("screen", [])):
		var l: Label = Label.new()
		l.text = str(line)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 26)
		column.add_child(l)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	column.add_child(row)
	use_button = _choice(str(_text.get("use", "")), MicMode.Mode.USE)
	mute_button = _choice(str(_text.get("mute", "")), MicMode.Mode.MUTE)
	row.add_child(use_button)
	row.add_child(mute_button)
	use_button.focus_neighbor_right = use_button.get_path_to(mute_button)
	mute_button.focus_neighbor_left = mute_button.get_path_to(use_button)
	notice_link = LinkButton.new()
	notice_link.text = str(_text.get("notice_link", ""))
	notice_link.focus_mode = Control.FOCUS_NONE
	notice_link.add_theme_font_size_override("font_size", 24)
	notice_link.pressed.connect(open_notice)
	column.add_child(notice_link)
	# Nothing selected or focused: the choice is the player's to make.
	get_viewport().gui_release_focus.call_deferred()


## Both buttons alike in every way but their words.
func _choice(text: String, mode: MicMode.Mode) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.toggle_mode = false
	b.focus_mode = Control.FOCUS_ALL
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_stretch_ratio = 1.0
	b.custom_minimum_size = Vector2(0, 80)
	b.add_theme_font_size_override("font_size", 28)
	b.pressed.connect(choose.bind(mode))
	return b


func _unhandled_input(event: InputEvent) -> void:
	if notice_panel != null:
		if event.is_action_pressed(&"ui_cancel"):
			close_notice()
			get_viewport().set_input_as_handled()
		return
	# The first left or right focuses that side; after that, focus moves and ui_accept presses.
	if get_viewport().gui_get_focus_owner() == null:
		if event.is_action_pressed(&"ui_left"):
			use_button.grab_focus()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(&"ui_right"):
			mute_button.grab_focus()
			get_viewport().set_input_as_handled()


func choose(mode: MicMode.Mode) -> void:
	if mic_mode != null:
		mic_mode.set_mode(mode)
	chosen.emit(mode)


func open_notice() -> void:
	if notice_panel != null:
		return
	# Opaque, over the whole screen; the text in a readable column with room to scroll.
	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = Color.BLACK
	bg.content_margin_left = 48
	bg.content_margin_right = 48
	bg.content_margin_top = 32
	bg.content_margin_bottom = 32
	panel.add_theme_stylebox_override("panel", bg)
	var centre: CenterContainer = CenterContainer.new()
	panel.add_child(centre)
	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size = Vector2(980, 0)
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 18)
	centre.add_child(column)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(980, 780)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var body: Label = Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("font_size", 26)
	body.text = "\n\n".join(PackedStringArray(Variants.array(_text.get("notice", []))))
	scroll.add_child(body)
	var close: Button = Button.new()
	close.text = str(_text.get("close", ""))
	close.custom_minimum_size = Vector2(300, 72)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.add_theme_font_size_override("font_size", 28)
	close.pressed.connect(close_notice)
	column.add_child(close)
	add_child(panel)
	notice_panel = panel
	close.grab_focus()


func close_notice() -> void:
	if notice_panel == null:
		return
	notice_panel.queue_free()
	notice_panel = null
	get_viewport().gui_release_focus()
