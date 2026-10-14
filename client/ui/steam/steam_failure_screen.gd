class_name SteamFailureScreen
extends Control
## STM-01: a release build that cannot start Steam shows this plain screen: what is wrong, what to do,
## and one Quit button. It has focus from the start; a controller alone works it (A, B or Start), as
## do Enter, Space or Escape. Quitting exits with ExitCode.STEAM_INIT_FAILED (4).

signal quit_requested(code: int)

var quit_button: Button = Button.new()
var body: Label = Label.new()


func _init(status: int) -> void:
	name = "SteamFailure"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel: ColorRect = ColorRect.new()
	panel.color = Color(0.05, 0.05, 0.06)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(900, 0)
	box.position = Vector2(-450, -160)
	box.add_theme_constant_override("separation", 32)
	add_child(box)
	var title: Label = Label.new()
	title.text = UiText.text("steam.failure.title")
	title.add_theme_font_size_override("font_size", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	body.text = UiText.text(body_key(status))
	body.add_theme_font_size_override("font_size", 28)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(body)
	quit_button.text = UiText.text("steam.failure.quit")
	quit_button.add_theme_font_size_override("font_size", 32)
	quit_button.custom_minimum_size = Vector2(320, 72)
	quit_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quit_button.pressed.connect(_quit)
	box.add_child(quit_button)


static func body_key(status: int) -> String:
	match status:
		SteamApi.Init.NO_STEAM_CLIENT:
			return "steam.failure.no_client"
		SteamApi.Init.VERSION_MISMATCH:
			return "steam.failure.out_of_date"
	return "steam.failure.other"


func _ready() -> void:
	quit_button.grab_focus()


func _input(event: InputEvent) -> void:
	# Godot's ui_accept and ui_cancel carry no pad buttons, so the pad is read here: A, B or Start.
	var pad: InputEventJoypadButton = event as InputEventJoypadButton
	if pad != null and pad.pressed and pad.button_index in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_START]:
		get_viewport().set_input_as_handled()
		_quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_quit()


func _quit() -> void:
	quit_requested.emit(ExitCode.STEAM_INIT_FAILED)
