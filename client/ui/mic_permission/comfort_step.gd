class_name ComfortStep
extends Control
## SND-10's stand-in for UI-06's comfort screen (GDD §14.5): the first Play shows it before the
## microphone screen. Only a Continue button until UI-06 sets captions, text size, flash reduction
## and brightness here.

signal done

var continue_button: Button = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var centre: CenterContainer = CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	centre.add_child(column)
	var label: Label = Label.new()
	label.text = "Comfort settings (UI-06)"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 26)
	column.add_child(label)
	continue_button = Button.new()
	continue_button.text = "Continue"
	continue_button.custom_minimum_size = Vector2(320, 56)
	continue_button.pressed.connect(func() -> void: done.emit())
	column.add_child(continue_button)
	continue_button.grab_focus.call_deferred()
