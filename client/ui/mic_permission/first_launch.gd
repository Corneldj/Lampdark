class_name FirstLaunch
extends Control
## SND-10: what Play leads to before any lobby (GDD §14.4). The first time, the comfort step, then
## the microphone permission screen; after a revised notice, the permission screen alone; once
## chosen, nothing. `finished` fires when the lobby may follow.

signal finished

var mic_mode: MicMode = null
var step: Control = null


func _init(mode: MicMode) -> void:
	mic_mode = mode


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if mic_mode.first_launch():
		var comfort: ComfortStep = ComfortStep.new()
		comfort.done.connect(_show_permission)
		_show(comfort)
	elif mic_mode.needs_choice():
		_show_permission()
	else:
		finished.emit.call_deferred()


func _show_permission() -> void:
	var screen: MicPermissionScreen = MicPermissionScreen.new(mic_mode)
	screen.chosen.connect(func(_mode: int) -> void: finished.emit())
	_show(screen)


func _show(next: Control) -> void:
	if step != null:
		step.queue_free()
	step = next
	add_child(next)
