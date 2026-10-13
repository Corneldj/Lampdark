extends GutTest
## FND-09: --link reaches the bot's TransportFilter, and the kit's link() configures its own.

const BotClient = preload("res://tools/bots/bot_client.gd")
const Scenario = preload("res://tests/scenario/kit/scenario.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_the_link_flag_parses() -> void:
	var build: BuildInfo = BuildInfo.detect(FeatureProvider.Fixed.new(PackedStringArray(["editor"])))
	var args: LaunchArgs = LaunchArgs.parse(PackedStringArray(), PackedStringArray(["--bot", "wander", "--link", "120,2.5",
		"--bot-seed", "18446744073709551615", "--receive-log", "user://r.log"]), build)
	assert_true(args.ok, args.error)
	assert_eq(args.client.link_rtt_ms, 120)
	assert_eq(args.client.link_loss_pct, 2.5)
	assert_eq(args.client.bot_seed, -1, "u64 max held in an int's bits")
	assert_eq(args.client.receive_log_path, "user://r.log")
	var release: BuildInfo = BuildInfo.detect(FeatureProvider.Fixed.new(PackedStringArray(["lb_client", "lb_release"])))
	var in_release: LaunchArgs = LaunchArgs.parse(PackedStringArray(), PackedStringArray(["--link", "120,2", "--bot", "idle"]), release)
	assert_eq(in_release.client.link_rtt_ms, -1, "release builds ignore --link")
	assert_eq(in_release.client.bot_script, "", "and --bot")
	for bad: String in ["120", "a,2", "120,101", "-5,1"]:
		var refused: LaunchArgs = LaunchArgs.parse(PackedStringArray(), PackedStringArray(["--link", bad]), build)
		assert_false(refused.ok, "--link %s is refused" % bad)


func test_the_bot_transport_carries_the_link_filter() -> void:
	var config: ClientConfig = ClientConfig.new()
	assert_true(BotClient.make_transport(config) is EnetTransport, "no --link, no filter")
	config.link_rtt_ms = 120
	config.link_loss_pct = 2.0
	var transport: Transport = BotClient.make_transport(config)
	assert_true(transport is LinkFilter)
	var filter: LinkFilter = transport
	assert_eq(filter.rtt_ms, 120)
	assert_eq(filter.loss_pct, 2.0)
	assert_true(filter.inner is EnetTransport, "the filter wraps the real transport")
	assert_true(filter is LinkEmulator, "NET-12's emulator")
	assert_false(filter.pass_through, "it emulates the link")


func test_the_kit_link_is_installed_per_miner() -> void:
	var s: Scenario = Scenario.create({"seed": 3})
	var h: RefCounted = s.add_miner("ann", Vector2i(1, 1))
	var link: LinkFilter = h.get(&"link_filter")
	assert_not_null(link)
	assert_eq(link.rtt_ms, 0)
	h.call(&"link", 80, 1.5)
	assert_eq([link.rtt_ms, link.loss_pct], [80, 1.5])
	assert_false(link.pass_through, "the kit's interim emulator delays and drops")
	s.close()
