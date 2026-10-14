extends GutTest
## STM-02's dev lobby by controller alone: MenuInput gives the menus pad buttons (Godot's ui_* carry
## none), focus starts on "Open a crew", the D-pad moves it, A presses, and in a crew focus lands on
## Ready; streamer mode shows the code masked; the overlay invite falls back to the code.

const R = preload("res://tests/unit/client/net/steam/lobby_rig.gd")


func before_all() -> void:
	assert_true(Tuning.load_client())
	MenuInput.install()


func _pad(button: JoyButton) -> void:
	var e: InputEventJoypadButton = InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = true
	get_viewport().push_input(e)
	var up: InputEventJoypadButton = e.duplicate()
	up.pressed = false
	get_viewport().push_input(up)


func test_menu_input_maps_the_pad() -> void:
	var pairs: Dictionary = {&"ui_accept": JOY_BUTTON_A, &"ui_cancel": JOY_BUTTON_B, &"ui_down": JOY_BUTTON_DPAD_DOWN, &"ui_up": JOY_BUTTON_DPAD_UP}
	for action: StringName in pairs.keys():
		var e: InputEventJoypadButton = InputEventJoypadButton.new()
		e.button_index = pairs[action]
		e.pressed = true
		assert_true(e.is_action(action), "%s on the pad" % action)
	MenuInput.install()
	var count: int = 0
	for e: InputEvent in InputMap.action_get_events(&"ui_accept"):
		if e is InputEventJoypadButton:
			count += 1
	assert_eq(count, 1, "installing twice adds nothing")


func test_open_a_crew_and_ready_up_by_pad_alone() -> void:
	var rig: R.Rig = R.make(self)
	var s: LobbyService = rig.client("Ann")
	var screen: DevLobby = DevLobby.new(s, s.steam, true, "127.0.0.1:24600")
	add_child_autofree(screen)
	await wait_process_frames(2)
	assert_true(screen.create_button.has_focus(), "focus starts on Open a crew")
	_pad(JOY_BUTTON_DPAD_DOWN)
	await wait_process_frames(1)
	assert_true(screen.code_entry.has_focus(), "the D-pad moves focus")
	_pad(JOY_BUTTON_DPAD_UP)
	await wait_process_frames(1)
	_pad(JOY_BUTTON_A)
	await rig.settle()
	assert_eq(s.state, LobbyService.State.IN_LOBBY, "A opened a crew")
	await wait_process_frames(2)
	assert_true(screen.ready_button.has_focus(), "in a crew, focus lands on Ready")
	assert_true(screen.code_label.text.contains(s.code))
	_pad(JOY_BUTTON_A)
	await rig.settle()
	assert_true(s.is_ready, "A readied up")
	assert_true(screen.crew_list.text.contains("✓"))
	assert_true(screen.start_button.visible, "the host may go down")


func test_streamer_mode_and_no_overlay() -> void:
	var rig: R.Rig = R.make(self)
	var s: LobbyService = rig.client("Ann")
	var screen: DevLobby = DevLobby.new(s, s.steam, true, "")
	add_child_autofree(screen)
	s.create()
	await rig.settle()
	s.steam.streamer_mode = true
	screen.refresh()
	assert_false(screen.code_label.text.contains(s.code), "the code is masked")
	assert_false(screen.crew_list.text.contains("Ann"), "names are lamp numbers")
	assert_false(screen.who.text.contains("Ann"))
	screen.invite_button.pressed.emit()
	assert_eq(screen.status.text, UiText.text("lobby.invite_none"), "no overlay in dev mode: share the code")
