class_name MenuInput
extends RefCounted
## STM-02: menus by controller alone. Godot's ui_* actions carry no pad buttons, so the client adds
## them once at start: A accepts, B cancels, the D-pad and left stick move focus. MNR-15 owns the
## in-mine bindings; these are only the menus' (UI-05 may make them rebindable).

const STICK_DEADZONE: float = 0.5


static func install() -> void:
	_button(&"ui_accept", JOY_BUTTON_A)
	_button(&"ui_cancel", JOY_BUTTON_B)
	_button(&"ui_up", JOY_BUTTON_DPAD_UP)
	_button(&"ui_down", JOY_BUTTON_DPAD_DOWN)
	_button(&"ui_left", JOY_BUTTON_DPAD_LEFT)
	_button(&"ui_right", JOY_BUTTON_DPAD_RIGHT)
	_axis(&"ui_up", JOY_AXIS_LEFT_Y, -1.0)
	_axis(&"ui_down", JOY_AXIS_LEFT_Y, 1.0)
	_axis(&"ui_left", JOY_AXIS_LEFT_X, -1.0)
	_axis(&"ui_right", JOY_AXIS_LEFT_X, 1.0)


static func _button(action: StringName, button: JoyButton) -> void:
	for e: InputEvent in InputMap.action_get_events(action):
		var b: InputEventJoypadButton = e as InputEventJoypadButton
		if b != null and b.button_index == button:
			return
	var ev: InputEventJoypadButton = InputEventJoypadButton.new()
	ev.button_index = button
	ev.device = -1
	InputMap.action_add_event(action, ev)


static func _axis(action: StringName, axis: JoyAxis, sign_of: float) -> void:
	for e: InputEvent in InputMap.action_get_events(action):
		var m: InputEventJoypadMotion = e as InputEventJoypadMotion
		if m != null and m.axis == axis and signf(m.axis_value) == sign_of:
			return
	var ev: InputEventJoypadMotion = InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = sign_of
	ev.device = -1
	InputMap.action_add_event(action, ev)
	if InputMap.action_get_deadzone(action) < STICK_DEADZONE:
		InputMap.action_set_deadzone(action, STICK_DEADZONE)
