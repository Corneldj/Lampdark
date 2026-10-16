extends GutTest
## Launch-argument parsing (FND-03).


func _build(tags: PackedStringArray) -> BuildInfo:
	return BuildInfo.detect(FeatureProvider.Fixed.new(tags))


func _dev() -> BuildInfo:
	return _build(PackedStringArray(["editor"]))


func _release_client() -> BuildInfo:
	return _build(PackedStringArray(["lb_client", "lb_release"]))


func _parse_user(args: Array[String], build: BuildInfo) -> LaunchArgs:
	return LaunchArgs.parse(PackedStringArray(), PackedStringArray(args), build)


func test_defaults() -> void:
	var parsed: LaunchArgs = _parse_user([], _dev())
	assert_true(parsed.ok)
	assert_false(parsed.wants_server)
	assert_eq(parsed.server.mode, ServerConfig.Mode.FRIENDS)
	assert_eq(parsed.server.transport, ServerConfig.TransportKind.ENET)
	assert_eq(parsed.server.port, 0)
	assert_eq(parsed.server.exit_after_ticks, 0)
	assert_eq(parsed.client.connect_target, "")
	assert_eq(parsed.log_level, "info")
	assert_eq(parsed.warnings.size(), 0)


func test_server_arguments() -> void:
	var parsed: LaunchArgs = _parse_user(["--server", "--mode", "nightshift", "--transport", "sdr",
		"--port", "27015", "--offline", "--parent-pid", "4242", "--control-port", "27020",
		"--resume", "user://saves/a.sav", "--exit-after-ticks", "40"], _dev())
	assert_true(parsed.ok, parsed.error)
	assert_true(parsed.wants_server)
	assert_eq(parsed.server.mode, ServerConfig.Mode.NIGHTSHIFT)
	assert_eq(parsed.server.transport, ServerConfig.TransportKind.SDR)
	assert_eq(parsed.server.port, 27015)
	assert_true(parsed.server.offline)
	assert_eq(parsed.server.parent_pid, 4242)
	assert_eq(parsed.server.control_port, 27020)
	assert_eq(parsed.server.resume_path, "user://saves/a.sav")
	assert_eq(parsed.server.exit_after_ticks, 40)


func test_director_on_a_fixed_map_only_when_asked() -> void:
	var plain: LaunchArgs = _parse_user(["--server", "--map", "m1_greybox"], _dev())
	assert_true(plain.ok, plain.error)
	assert_false(plain.server.director, "QA-01's grey box runs without the Director")
	var asked: LaunchArgs = _parse_user(["--server", "--map", "m1_greybox", "--director"], _dev())
	assert_true(asked.server.director)
	var released: LaunchArgs = _parse_user(["--server", "--director"], _build(PackedStringArray(["lb_server", "lb_release"])))
	assert_true(released.server.director, "not a dev-only flag")


func test_loopback_shorthand_and_inline_values() -> void:
	var parsed: LaunchArgs = _parse_user(["--loopback", "--mode=public", "--log-level=debug"], _dev())
	assert_true(parsed.ok, parsed.error)
	assert_eq(parsed.server.transport, ServerConfig.TransportKind.LOOPBACK)
	assert_eq(parsed.server.mode, ServerConfig.Mode.PUBLIC)
	assert_eq(parsed.log_level, "debug")


func test_client_dev_arguments() -> void:
	var parsed: LaunchArgs = _parse_user(["--connect", "127.0.0.1:7777", "--no-steam",
		"--name", "Tester", "--bot", "res://tools/bots/walk.gd", "--qa-token", "t0k"], _dev())
	assert_true(parsed.ok, parsed.error)
	assert_eq(parsed.client.connect_target, "127.0.0.1:7777")
	assert_true(parsed.client.no_steam)
	assert_eq(parsed.client.persona_name, "Tester")
	assert_eq(parsed.client.bot_script, "res://tools/bots/walk.gd")
	assert_eq(parsed.client.qa_token, "t0k")
	assert_eq(parsed.server.qa_token, "t0k")


func test_steam_connect_lobby_before_double_dash() -> void:
	var engine_args: PackedStringArray = PackedStringArray(["--headless", "+connect_lobby",
		"109775241234567890", "--some-engine-option"])
	var parsed: LaunchArgs = LaunchArgs.parse(engine_args, PackedStringArray(), _release_client())
	assert_true(parsed.ok, parsed.error)
	assert_eq(parsed.client.connect_lobby, "109775241234567890")
	assert_eq(parsed.warnings.size(), 0, "engine options before -- are left to the engine")


func test_known_flags_before_double_dash_are_read() -> void:
	var engine_args: PackedStringArray = PackedStringArray(["--headless", "--exit-after-ticks", "40"])
	var parsed: LaunchArgs = LaunchArgs.parse(engine_args, PackedStringArray(), _dev())
	assert_true(parsed.ok, parsed.error)
	assert_eq(parsed.server.exit_after_ticks, 40)


func test_unknown_argument_warns() -> void:
	var parsed: LaunchArgs = _parse_user(["--bogus", "--server"], _dev())
	assert_true(parsed.ok)
	assert_true(parsed.wants_server)
	assert_eq(parsed.warnings.size(), 1)
	assert_string_contains(parsed.warnings[0], "--bogus")


func test_malformed_values_fail() -> void:
	var cases: Array[Array] = [
		["--port", "0"], ["--port", "65536"], ["--port", "abc"], ["--mode", "solo"],
		["--transport", "tcp"], ["--connect", "nohost"], ["--connect", "host:99999"],
		["--seed", "-1"], ["--seed", "18446744073709551616"], ["--exit-after-ticks", "0"],
		["--log-level", "loud"], ["--port"], ["--mode", "--server"],
	]
	for case: Array in cases:
		var args: Array[String] = []
		for item: Variant in case:
			args.append(str(item))
		var parsed: LaunchArgs = _parse_user(args, _dev())
		assert_false(parsed.ok, "malformed: %s" % " ".join(PackedStringArray(args)))
		assert_ne(parsed.error, "", "an error message explains %s" % args[0])


func test_refused_in_release_are_ignored_with_warning() -> void:
	var refused: Array[Array] = [
		["--connect", "10.0.0.1:7777"], ["--no-steam"], ["--name", "X"], ["--seed", "42"],
		["--qa-token", "t"], ["--bot", "b.gd"], ["--exit-after-ticks", "40"],
	]
	for case: Array in refused:
		var args: Array[String] = []
		for item: Variant in case:
			args.append(str(item))
		var parsed: LaunchArgs = _parse_user(args, _release_client())
		assert_true(parsed.ok, "refused %s does not fail the parse" % args[0])
		assert_eq(parsed.warnings.size(), 1, "refused %s warns" % args[0])
		assert_eq(parsed.client.connect_target, "")
		assert_false(parsed.client.no_steam)
		assert_eq(parsed.client.persona_name, "")
		assert_false(parsed.server.has_seed)
		assert_eq(parsed.client.qa_token, "")
		assert_eq(parsed.client.bot_script, "")
		assert_eq(parsed.client.exit_after_ticks, 0)


func test_refused_still_needs_its_value_consumed() -> void:
	var parsed: LaunchArgs = _parse_user(["--seed", "42", "--mode", "public"], _release_client())
	assert_true(parsed.ok)
	assert_eq(parsed.server.mode, ServerConfig.Mode.PUBLIC, "the next argument still parses")


func test_qa_accepts_dev_arguments() -> void:
	var qa: BuildInfo = _build(PackedStringArray(["lb_client", "lb_qa"]))
	var parsed: LaunchArgs = _parse_user(["--seed", "7", "--exit-after-ticks", "5"], qa)
	assert_true(parsed.ok)
	assert_true(parsed.server.has_seed)
	assert_eq(parsed.client.exit_after_ticks, 5)
	assert_eq(parsed.warnings.size(), 0)


func test_u64_round_trip() -> void:
	for text: String in ["0", "1", "42", "4294967295", "4294967296", "9223372036854775807",
			"9223372036854775808", "18446744073709551615"]:
		var parsed: Array = LaunchArgs.parse_u64(text)
		var parsed_ok: bool = parsed[0]
		assert_true(parsed_ok, "parses " + text)
		var value: int = parsed[1]
		assert_eq(LaunchArgs.u64_to_string(value), text, "round trip " + text)
	var max_value: int = LaunchArgs.parse_u64("18446744073709551615")[1]
	assert_eq(max_value, -1, "2^64-1 holds all 64 bits")
