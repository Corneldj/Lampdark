extends GutTest
## MOD-03 (Gameplay §12.6; GDD §13.8): lobby metadata carries the options alone. Whatever run they
## make (here a staged one with a plan and a draw), the seed, the draw, the staging level and the plan
## appear nowhere in the lobby's data, a member's data or the Welcome; the options' lobby form is
## exactly {mode, list, hard, hands}. Steam rich presence (STM-11) is not built yet; it may show the
## mode and the list, from the same form. NET-08's audit makes the same check on every message sent
## (tests/scenario/modes/test_no_secrets_on_the_wire.gd).

const Specs = preload("res://tests/unit/gen/template_specs.gd")
const SEED: int = 0x5DEECE66D2B7E151

var _hub: InProcessTransport.Hub = null


func before_all() -> void:
	assert_true(Tuning.load_server())


## The run's secrets as text a lobby value could hold: the seed in decimal and hex (both byte
## orders), the plan's bytes as hex, the drawn names.
static func _needles(run: RunState) -> Array[String]:
	var le: PackedByteArray = PackedByteArray()
	le.resize(8)
	le.encode_s64(0, run.header.run_seed)
	var be: PackedByteArray = le.duplicate()
	be.reverse()
	var out: Array[String] = [str(run.header.run_seed), LbHash.to_hex(run.header.run_seed), le.hex_encode(), be.hex_encode(),
		run.header.plan.slice(run.header.plan.size() / 2, run.header.plan.size() / 2 + 24).hex_encode()]
	for d: String in run.header.draw:
		out.append(d)
	return out


func _staged_run() -> RunState:
	_hub = InProcessTransport.Hub.new()
	var server: InProcessTransport = InProcessTransport.new(_hub)
	assert_eq(server.listen("server", 1), OK)
	var run: RunState = RunState.create(SEED, ServerConfig.Mode.FRIENDS, false)
	ServerSystems.install(run, ServerNet.new(server, 5))
	var options: RunOptions = RunOptions.defaults(ServerConfig.Mode.FRIENDS)
	options.hard_variant = "no_chalk"
	assert_eq(RunSetup.create(run, options, 2, [0, 1] as Array[int], RunSetup.unlocked_variants(true)), "")
	run.header.draw = PackedStringArray(["dry_stores", "pale_moth"])  # as HAZ-07 will draw them
	var layouts: LbLayouts = LbLayouts.new()
	assert_true(layouts.load_pack(Specs.road_pack()))
	MineLayouts.configure(layouts, SEED)
	assert_false(RunPlan.fix(layouts, run, PackedByteArray(), {"data_version": "test", "tuning": {}}).is_empty())
	assert_eq(run.header.staging, "1", "a staged run")
	assert_gt(run.header.plan.size(), 1000, "with a plan")
	return run


func test_the_lobby_form_is_the_options_alone() -> void:
	var o: RunOptions = RunOptions.defaults(ServerConfig.Mode.FRIENDS)
	var keys: Array = o.to_dict().keys()
	keys.sort()
	assert_eq(keys, ["hands", "hard", "list", "mode"], "mode, list, hard variant, Hands: nothing else")


func test_no_secret_reaches_the_lobby_or_a_member() -> void:
	var run: RunState = _staged_run()
	var lobby: Dictionary = LobbyMetadata.lobby_data(run.header.options.to_dict(), LobbyMetadata.RUNNING, "BLACK-DAMP", "", true)
	assert_eq(str(lobby["lb_mode"]), "friends")
	assert_eq(str(lobby["lb_list"]), "standard", "the host's list, not the staged run's Short one")
	assert_eq(str(lobby["lb_hard"]), "no_chalk")
	for k: Variant in lobby.keys():
		assert_true(LobbyMetadata.LOBBY_KEYS.has(str(k)), "%s is a lobby key" % k)
		for word: String in ["seed", "draw", "staging", "plan", "spine"]:
			assert_false(str(k).contains(word), "no key names the %s" % word)
	var member: Dictionary = LobbyMetadata.member_data(true, "Ada Rowe", 114, 3, false)
	var texts: Array[String] = []
	for d: Dictionary in [lobby, member]:
		for v: Variant in d.values():
			texts.append(str(v))
	for needle: String in _needles(run):
		for t: String in texts:
			assert_false(t.contains(needle), "'%s' carries no secret (%s)" % [t, needle])


func test_no_secret_rides_the_welcome() -> void:
	var run: RunState = _staged_run()
	var c: ClientConnection = ClientConnection.new(InProcessTransport.new(_hub))
	c.identity = "ann"
	c.candidates = [{"id": 1, "name": "Ada Rowe", "lamp_number": 114, "voice_id": 1, "book_pages": []}] as Array[Dictionary]
	assert_true(c.start("server", 1))
	for _i: int in 6:
		c.poll()
		run.run_tick()
	c.poll()
	assert_eq(c.state, ClientConnection.State.CONNECTED)
	var w: Protocol.Welcome = c.welcome
	assert_eq(w.run_uuid, run.header.run_uuid, "the run's identity may be known (RSC-06 sends a miner Below for it)")
	var hex: String = w.encode().hex_encode()
	for needle: String in _needles(run):
		assert_false(hex.contains(needle) or hex.contains(needle.to_utf8_buffer().hex_encode()), "no %s in the Welcome" % needle)
