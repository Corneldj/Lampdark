extends GutTest
## SND-10: the permission screen. Both buttons identical in size, font and colour; nothing focused
## when it opens; the first left or right focuses a side and accept confirms; the notice opens and
## closes (a mouse click, which needs a window, is in tests/unit/ui/window/). And the first-launch flow: comfort step, then this screen,
## before the lobby; after a raised notice version, this screen alone.

var _dir: String = ""


func before_each() -> void:
	_dir = "user://test_mic_screen_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)


func after_each() -> void:
	for f: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(f))
	DirAccess.remove_absolute(_dir)


func _mode(version: int = 1) -> MicMode:
	var v: String = _dir.path_join("version.json")
	var f: FileAccess = FileAccess.open(v, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": version}))
	f.close()
	return MicMode.new(_dir.path_join("log.jsonl"), _dir.path_join("queue.jsonl"), v)


## On a layer above GUT's own panels, as the screen is above everything in the game.
func _screen(m: MicMode) -> MicPermissionScreen:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 100
	add_child_autofree(layer)
	var s: MicPermissionScreen = MicPermissionScreen.new(m)
	layer.add_child(s)
	await wait_physics_frames(3)
	return s


func _action(name: StringName) -> void:
	for pressed: bool in [true, false]:
		var e: InputEventAction = InputEventAction.new()
		e.action = name
		e.pressed = pressed
		get_viewport().push_input(e)


func test_the_two_buttons_are_identical_and_nothing_is_focused() -> void:
	var s: MicPermissionScreen = await _screen(_mode())
	assert_eq(s.use_button.size, s.mute_button.size, "equal size")
	assert_gt(s.use_button.size.x, 100.0)
	assert_eq(s.use_button.get_theme_font_size("font_size"), s.mute_button.get_theme_font_size("font_size"), "equal font size")
	assert_eq(s.use_button.get_theme_font("font"), s.mute_button.get_theme_font("font"), "equal font")
	assert_eq(s.use_button.get_theme_color("font_color"), s.mute_button.get_theme_color("font_color"), "equal colour")
	assert_eq(s.use_button.get_theme_stylebox("normal"), s.mute_button.get_theme_stylebox("normal"), "equal style")
	assert_false(s.use_button.button_pressed or s.mute_button.button_pressed, "neither selected")
	assert_null(get_viewport().gui_get_focus_owner(), "neither focused")
	assert_eq(s.use_button.text, "Use my microphone")
	assert_eq(s.mute_button.text, "Mute (callouts and taps only)")


func test_right_then_accept_chooses_mute() -> void:
	var m: MicMode = _mode()
	m.set_mode(MicMode.Mode.USE)  # a revised choice: Mute must win from the screen
	var s: MicPermissionScreen = await _screen(m)
	var got: Array = []
	s.chosen.connect(func(mode: int) -> void: got.append(mode))
	_action(&"ui_right")
	await wait_physics_frames(1)
	assert_eq(get_viewport().gui_get_focus_owner(), s.mute_button, "right focuses Mute")
	_action(&"ui_accept")
	await wait_physics_frames(2)
	assert_eq(got, [MicMode.Mode.MUTE])
	assert_eq(m.mode, MicMode.Mode.MUTE)


func test_left_then_accept_chooses_use() -> void:
	var m: MicMode = _mode()
	var s: MicPermissionScreen = await _screen(m)
	_action(&"ui_left")
	await wait_physics_frames(1)
	assert_eq(get_viewport().gui_get_focus_owner(), s.use_button, "left focuses Use")
	_action(&"ui_accept")
	await wait_physics_frames(2)
	assert_eq(m.mode, MicMode.Mode.USE)


func test_the_notice_opens_and_closes() -> void:
	var s: MicPermissionScreen = await _screen(_mode())
	s.open_notice()
	await wait_physics_frames(1)
	assert_not_null(s.notice_panel)
	s.close_notice()
	await wait_physics_frames(1)
	assert_null(s.notice_panel)
	assert_null(get_viewport().gui_get_focus_owner(), "back to nothing focused")


func test_first_launch_shows_comfort_then_this_screen() -> void:
	var m: MicMode = _mode()
	var flow: FirstLaunch = FirstLaunch.new(m)
	var done: Array = []
	flow.finished.connect(func() -> void: done.append(true))
	add_child_autofree(flow)
	await wait_physics_frames(2)
	assert_true(flow.step is ComfortStep, "the comfort step first")
	(flow.step as ComfortStep).continue_button.pressed.emit()
	await wait_physics_frames(2)
	assert_true(flow.step is MicPermissionScreen, "then the microphone screen")
	assert_eq(done.size(), 0, "no lobby yet")
	(flow.step as MicPermissionScreen).mute_button.pressed.emit()
	await wait_physics_frames(1)
	assert_eq(done.size(), 1, "the lobby may follow")


func test_a_raised_version_shows_only_this_screen_and_a_chosen_one_nothing() -> void:
	var m: MicMode = _mode(1)
	m.set_mode(MicMode.Mode.USE)
	var same: FirstLaunch = FirstLaunch.new(_mode(1))
	var done: Array = []
	same.finished.connect(func() -> void: done.append(true))
	add_child_autofree(same)
	await wait_physics_frames(2)
	assert_eq(done.size(), 1, "already chosen: straight on")
	var revised: FirstLaunch = FirstLaunch.new(_mode(2))
	add_child_autofree(revised)
	await wait_physics_frames(2)
	assert_true(revised.step is MicPermissionScreen, "a revised notice asks again, without the comfort step")


func test_play_in_the_client_leads_through_the_screens_to_the_lobby() -> void:
	var script: GDScript = load("res://client/client_main.gd")
	var cm: Node = script.new()
	cm.set("mic_mode", _mode())
	add_child_autofree(cm)
	cm.call("_show_pithead")
	var play: Button = cm.find_child("Play", true, false)
	assert_not_null(play, "the Pithead's Play")
	assert_null(cm.find_child("DevLobby", true, false), "no lobby before Play")
	play.pressed.emit()
	await wait_physics_frames(2)
	var flow: FirstLaunch = cm.find_child("FirstLaunch", true, false)
	assert_not_null(flow, "Play leads to the first-launch screens")
	assert_true(flow.step is ComfortStep)
	assert_null(cm.find_child("DevLobby", true, false), "still no lobby")
	(flow.step as ComfortStep).continue_button.pressed.emit()
	await wait_physics_frames(2)
	(flow.step as MicPermissionScreen).mute_button.pressed.emit()
	await wait_physics_frames(2)
	assert_not_null(cm.find_child("DevLobby", true, false), "the lobby once chosen")


## In play the lobby gives way to the mine; refused or lost, it comes back to connect again; and a
## client already in play (launched with --connect) skips it after the first-launch screens.
func test_the_lobby_hides_in_play_and_returns_on_a_drop() -> void:
	var script: GDScript = load("res://client/client_main.gd")
	var cm: Node = script.new()
	cm.set("mic_mode", _mode())
	add_child_autofree(cm)
	cm.set("_first_launch_done", true)
	cm.call("_show_dev_lobby")
	assert_not_null(cm.find_child("DevLobby", true, false), "the lobby")
	var c: ClientConnection = ClientConnection.new(InProcessTransport.new(InProcessTransport.Hub.new()))
	c.welcome = Protocol.Welcome.new()
	c.state = ClientConnection.State.CONNECTED
	cm.set("connection", c)
	cm.call("_report_connection")
	await wait_physics_frames(2)
	assert_null(cm.find_child("DevLobby", true, false), "hidden in play")
	cm.call("_show_dev_lobby")
	assert_null(cm.find_child("DevLobby", true, false), "not shown again while in play")
	assert_false(Variants.flag(cm.call("_may_connect")), "no second connection while in play")
	c.state = ClientConnection.State.DROPPED
	cm.call("_report_connection")
	await wait_physics_frames(2)
	assert_not_null(cm.find_child("DevLobby", true, false), "back to the lobby on a drop")
	assert_true(Variants.flag(cm.call("_may_connect")), "free to connect again")
