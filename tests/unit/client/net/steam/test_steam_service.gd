extends GutTest
## STM-01's SteamService against a fake Steam: the init statuses by flavour, dev mode and its fake
## identity (no GodotSteam call after a failed init), the relaunch check, the callback pump (paused
## too), ordered shutdown, names under streamer mode, persona changes and the overlay.

const Fake = preload("res://tests/unit/client/net/steam/fake_steam_api.gd")
const F = preload("res://tests/unit/mnr/input_frames.gd")


func before_all() -> void:
	assert_true(Tuning.load_client())


func _service(fake: SteamApi) -> SteamService:
	var s: SteamService = SteamService.new(fake)
	add_child_autofree(s)
	return s


func test_status_mapping() -> void:
	assert_eq(SteamService.outcome_for(SteamApi.Init.OK, true), SteamService.Boot.CONTINUE)
	assert_eq(SteamService.outcome_for(SteamApi.Init.OK, false), SteamService.Boot.CONTINUE)
	for status: int in [SteamApi.Init.FAILED_GENERIC, SteamApi.Init.NO_STEAM_CLIENT, SteamApi.Init.VERSION_MISMATCH]:
		assert_eq(SteamService.outcome_for(status, true), SteamService.Boot.FAIL, "release: failure screen, exit 4 (%d)" % status)
		assert_eq(SteamService.outcome_for(status, false), SteamService.Boot.CONTINUE, "dev or QA: dev mode (%d)" % status)
	assert_eq(ExitCode.STEAM_INIT_FAILED, 4)


func test_steam_up_gives_identity_language_and_hardware() -> void:
	var fake: SteamApi = Fake.new()
	fake.set(&"hardware_value", SteamApi.Hardware.STEAM_DECK)
	var s: SteamService = _service(fake)
	assert_eq(s.boot(false, false, ""), SteamService.Boot.CONTINUE)
	assert_eq(s.mode, SteamService.Mode.STEAM)
	assert_true(s.available())
	assert_eq(s.steam_id, 76561197960287930)
	assert_eq(s.persona_name(), "Ann")
	assert_false(s.fake_identity)
	assert_eq(s.language(), "english", "Steam's game language seeds UI-07's default")
	assert_eq(s.steam_hardware(), SteamApi.Hardware.STEAM_DECK, "for STM-07's defaults")
	assert_true(s.overlay_enabled())
	assert_false(Variants.array(fake.get(&"calls")).has("restart_app_if_necessary"), "dev and QA builds never relaunch")


func test_no_steam_is_dev_mode_with_no_steam_call() -> void:
	var fake: SteamApi = Fake.new()
	var s: SteamService = _service(fake)
	assert_eq(s.boot(false, true, "Ann"), SteamService.Boot.CONTINUE)
	assert_eq(s.mode, SteamService.Mode.DEV)
	assert_true(s.fake_identity)
	assert_eq(s.persona_name(), "Ann")
	assert_eq(Variants.array(fake.get(&"calls")), [], "--no-steam: GodotSteam is never called")


func test_a_failed_init_is_dev_mode_and_steam_is_left_alone() -> void:
	for status: int in [SteamApi.Init.FAILED_GENERIC, SteamApi.Init.NO_STEAM_CLIENT, SteamApi.Init.VERSION_MISMATCH]:
		var fake: SteamApi = Fake.new()
		fake.set(&"init_status", status)
		var s: SteamService = _service(fake)
		assert_eq(s.boot(false, false, "Bo"), SteamService.Boot.CONTINUE)
		assert_eq(s.mode, SteamService.Mode.DEV)
		# Everything a later ticket might ask, and a few frames of the pump.
		s.display_name(12345)
		s.overlay_enabled()
		s.language()
		s.steam_hardware()
		await wait_process_frames(3)
		s.shutdown()
		assert_eq(Variants.array(fake.get(&"calls")), ["init"], "status %d: no GodotSteam call after the failed init" % status)
		assert_false(s.available(), "every Steam service reports unavailable")
		assert_false(s.overlay_enabled())
		assert_eq(s.language(), "")


func test_the_fake_identity_is_stable_and_steamid_shaped() -> void:
	var a: int = SteamService.fake_steam_id("Ann")
	assert_eq(a, SteamService.fake_steam_id("Ann"), "stable for a name")
	assert_ne(a, SteamService.fake_steam_id("Bo"))
	assert_between(a, SteamService.STEAM_ID_BASE, SteamService.STEAM_ID_BASE + 0xFFFFFFFF, "an individual SteamID64")
	var fake: SteamApi = Fake.new()
	var s: SteamService = _service(fake)
	s.boot(false, true, "")
	assert_eq(s.persona_name(), "dev")
	assert_eq(s.steam_id, SteamService.fake_steam_id("dev"))


func test_release_relaunches_through_steam_or_fails() -> void:
	var fake: SteamApi = Fake.new()
	fake.set(&"restart_value", true)
	var s: SteamService = _service(fake)
	assert_eq(s.boot(true, false, ""), SteamService.Boot.QUIT_RELAUNCHING, "launched outside Steam: relaunch and quit")
	assert_eq(Variants.array(fake.get(&"calls")), ["restart_app_if_necessary"], "no init before quitting")
	var down: SteamApi = Fake.new()
	down.set(&"init_status", SteamApi.Init.NO_STEAM_CLIENT)
	var r: SteamService = _service(down)
	assert_eq(r.boot(true, true, "x"), SteamService.Boot.FAIL, "release ignores --no-steam and never runs without Steam")
	assert_eq(r.mode, SteamService.Mode.FAILED)
	assert_eq(r.init_status, SteamApi.Init.NO_STEAM_CLIENT)


func test_callbacks_every_frame_even_paused() -> void:
	var fake: SteamApi = Fake.new()
	var s: SteamService = _service(fake)
	s.boot(false, false, "")
	await wait_process_frames(5)
	var before: int = Variants.array(fake.get(&"calls")).count("run_callbacks")
	assert_gte(before, 4)
	get_tree().paused = true
	await wait_process_frames(5)
	get_tree().paused = false
	assert_gte(Variants.array(fake.get(&"calls")).count("run_callbacks"), before + 4, "Night Shift's pause keeps them flowing")


func test_shutdown_runs_the_hooks_in_order_then_steam_once() -> void:
	var fake: SteamApi = Fake.new()
	var s: SteamService = _service(fake)
	s.boot(false, false, "")
	var seen: Array[String] = []
	s.add_shutdown_hook(30, "server", func() -> void: seen.append("stop server"))
	s.add_shutdown_hook(10, "lobby", func() -> void: seen.append("leave lobby"))
	s.add_shutdown_hook(40, "cloud", func() -> void: seen.append("end cloud batch"))
	s.add_shutdown_hook(20, "relay", func() -> void: seen.append("close connections"))
	var calls: Array = Variants.array(fake.get(&"calls"))
	s.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_eq(seen, ["leave lobby", "close connections", "stop server", "end cloud batch"] as Array[String])
	var last: String = str(calls.back())
	assert_eq(last, "shutdown", "Steam last")
	s.shutdown()
	assert_eq(calls.count("shutdown"), 1, "once")
	assert_eq(s.mode, SteamService.Mode.OFF)


func test_streamer_mode_never_shows_a_steam_name() -> void:
	var fake: SteamApi = Fake.new()
	fake.set(&"friends", {76561197960300000: "Bob"})
	var s: SteamService = _service(fake)
	s.boot(false, false, "")
	assert_eq(s.display_name(s.steam_id), "Ann")
	assert_eq(s.display_name(76561197960300000), "Bob")
	s.streamer_mode = true
	s.lamp_numbers = {s.steam_id: 3}
	assert_eq(s.display_name(s.steam_id), "Lamp 3")
	assert_eq(s.display_name(76561197960300000), "A miner", "no lamp number known: still no name")
	for id: int in [s.steam_id, 76561197960300000]:
		assert_false(s.display_name(id).contains("Ann") or s.display_name(id).contains("Bob"))


func test_a_persona_change_updates_names() -> void:
	var fake: SteamApi = Fake.new()
	var s: SteamService = _service(fake)
	s.boot(false, false, "")
	watch_signals(s)
	fake.call(&"change_persona", s.steam_id, "Annie")
	assert_signal_emitted_with_parameters(s, "persona_changed", [s.steam_id])
	assert_eq(s.display_name(s.steam_id), "Annie")
	fake.call(&"change_persona", 76561197960300001, "Cat")
	assert_eq(s.display_name(76561197960300001), "Cat")


func test_overlay_state_and_disabled_overlay() -> void:
	var fake: SteamApi = Fake.new()
	var s: SteamService = _service(fake)
	s.boot(false, false, "")
	watch_signals(s)
	fake.call(&"toggle_overlay", true)
	assert_true(s.overlay_active)
	assert_signal_emitted_with_parameters(s, "overlay_toggled", [true])
	assert_false(get_tree().paused, "nothing pauses")
	fake.call(&"toggle_overlay", false)
	assert_false(s.overlay_active)
	var off: SteamApi = Fake.new()
	off.set(&"overlay_on", false)
	var t: SteamService = _service(off)
	t.boot(false, false, "")
	assert_false(t.overlay_enabled(), "reported, so STM-02 offers codes instead of the invite dialog")


func test_the_overlay_releases_every_gameplay_input() -> void:
	var r: InputRouter = F.router()
	var held: Dictionary = {}
	for action: String in ["sprint", "crouch", "interact", "check_lamp", "squint"]:
		held[action] = true
	r.sample(F.frame(1.0, held, {"move": Vector2(1, 0)}))
	r.sample(F.frame(1.1, held, {"move": Vector2(1, 0)}))
	assert_ne(r.record.holds, 0, "holding before")
	r.release_all()
	r.sample(InputRouter.neutral_frame(F.frame(1.2, held, {"move": Vector2(1, 0)})))
	assert_eq(r.record.holds, 0, "the overlay: nothing held")
	assert_eq(r.record.move_dir, InputRecord.NO_DIRECTION, "the miner stands")
	r.sample(F.frame(2.0, {"callout": true}))
	assert_eq(r.context, InputContexts.Context.WHEEL)
	r.sample(InputRouter.neutral_frame(F.frame(2.1, {"callout": true}, {"wheel_vec": Vector2(0.9, 0)})))
	assert_eq(r.actions, [] as Array[Array], "an open wheel closes centred: nothing sent")
	var src: String = FileAccess.get_file_as_string("res://client/client_main.gd")
	assert_true(src.contains("frame = InputRouter.neutral_frame(frame)") and src.contains("router.release_all()"),
		"ClientMain feeds neutral frames while the overlay is open")
	assert_false(src.contains("paused = true"), "nothing pauses online")


func test_the_failure_screen_works_by_controller_alone() -> void:
	for status: int in [SteamApi.Init.NO_STEAM_CLIENT, SteamApi.Init.VERSION_MISMATCH, SteamApi.Init.FAILED_GENERIC]:
		var screen: SteamFailureScreen = SteamFailureScreen.new(status)
		add_child_autofree(screen)
		await wait_process_frames(1)
		assert_ne(screen.body.text, "", "plain text for status %d" % status)
		assert_true(screen.quit_button.has_focus(), "focused from the start")
		var codes: Array[int] = []
		screen.quit_requested.connect(func(code: int) -> void: codes.append(code))
		var a: InputEventJoypadButton = InputEventJoypadButton.new()
		a.button_index = JOY_BUTTON_A
		a.pressed = true
		get_viewport().push_input(a)
		await wait_process_frames(1)
		assert_eq(codes, [ExitCode.STEAM_INIT_FAILED] as Array[int], "pad A quits with exit code 4")
		var enter: InputEventKey = InputEventKey.new()
		enter.keycode = KEY_ENTER
		enter.pressed = true
		get_viewport().push_input(enter)
		var enter_up: InputEventKey = enter.duplicate()
		enter_up.pressed = false
		get_viewport().push_input(enter_up)
		await wait_process_frames(1)
		assert_eq(codes.size(), 2, "Enter on the focused button too")
	assert_eq(SteamFailureScreen.body_key(SteamApi.Init.NO_STEAM_CLIENT), "steam.failure.no_client")
	assert_eq(SteamFailureScreen.body_key(SteamApi.Init.VERSION_MISMATCH), "steam.failure.out_of_date")


func test_steamids_survive_exactly() -> void:
	# STM-02 found 64-bit IDs rounded through Variants.number's double: 76561198030964382 read back
	# as ...384. SteamIDs and lobby IDs go through Variants.whole.
	var real_id: int = 76561197960265728 + 70698654
	assert_eq(real_id, 76561198030964382)
	assert_ne(int(Variants.number(real_id)), real_id, "a double cannot hold it")
	assert_eq(Variants.whole(real_id), real_id)
	assert_eq(Variants.whole(str(real_id)), real_id, "from JSON's strings too")
	assert_eq(Variants.whole(3.9), 3)
	var src: String = FileAccess.get_file_as_string("res://shared/platform/steam/steam_api.gd")
	assert_false(src.contains("Variants.number"), "the adapter reads every Steam integer exactly")
