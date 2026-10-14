extends GutTest
## STM-02's LobbyService: a host opens a lobby of modes.friends_lobby_max with every key written; friends
## join by code (any case, O/I/L), by an accepted invite or "Join Game", or are refused (unknown code,
## full, another build); in M1 members connect to lb_dev_addr; release builds write no address;
## streamer mode hides the code and names.

const R = preload("res://tests/unit/client/net/steam/lobby_rig.gd")
const Fake = preload("res://tests/unit/client/net/steam/fake_steam_api.gd")


func before_all() -> void:
	assert_true(Tuning.load_client())


func test_a_host_opens_a_lobby_with_every_key() -> void:
	var rig: R.Rig = R.make(self)
	var ann: LobbyService = rig.client("Ann")
	var connects: Array[String] = []
	ann.connect_requested.connect(func(a: String) -> void: connects.append(a))
	ann.create()
	await rig.settle()
	assert_eq(ann.state, LobbyService.State.IN_LOBBY)
	assert_true(ann.is_host())
	var l: Dictionary = rig.server.lobbies[ann.backend.lobby_id]
	assert_eq(Variants.whole(l["limit"]), 5, "modes.friends_lobby_max")
	var data: Dictionary = l["data"]
	for key: String in LobbyMetadata.LOBBY_KEYS:
		assert_true(data.has(key), "%s written" % key)
	assert_eq(str(data["lb_code"]), ann.code)
	assert_eq(connects, ["127.0.0.1:24600"] as Array[String], "M1: the host connects to lb_dev_addr too")


func test_join_by_code_in_any_case_and_ready_up() -> void:
	var rig: R.Rig = R.make(self)
	var ann: LobbyService = rig.client("Ann")
	R.force_codes(ann, ["0B1C2D"])
	ann.create()
	await rig.settle()
	var bo: LobbyService = rig.client("Bo")
	var connects: Array[String] = []
	bo.connect_requested.connect(func(a: String) -> void: connects.append(a))
	bo.join_code("ob-ic 2d")  # O for 0, I and L for 1, lower case, a dash and a space
	await rig.settle()
	assert_eq(bo.state, LobbyService.State.IN_LOBBY)
	assert_eq(bo.backend.lobby_id, ann.backend.lobby_id)
	assert_eq(bo.code, "0B1C2D", "a joiner sees the code to share")
	assert_eq(connects, ["127.0.0.1:24600"] as Array[String], "M1: over ENet to lb_dev_addr")
	bo.set_ready(true)
	await rig.settle()
	var crew: Array[Dictionary] = ann.crew()
	assert_eq(crew.size(), 2)
	assert_eq(str(crew[0]["name"]), "Ann")
	assert_true(Variants.flag(crew[0]["host"]))
	assert_eq(str(crew[1]["name"]), "Bo")
	assert_true(Variants.flag(crew[1]["ready"]), "the host sees Bo ready")


func test_an_unknown_code_joins_nothing() -> void:
	var rig: R.Rig = R.make(self)
	var ann: LobbyService = rig.client("Ann")
	ann.create()
	await rig.settle()
	var bo: LobbyService = rig.client("Bo")
	var failures: Array[String] = []
	bo.failed.connect(func(k: String) -> void: failures.append(k))
	bo.join_code("ZZZZZZ" if ann.code != "ZZZZZZ" else "YYYYYY")
	await rig.settle()
	assert_eq(failures, [] as Array[String], "not yet: one more look after net.invite_code_retry_s")
	await rig.settle_retry()
	bo.join_code("not a code")
	await rig.settle()
	assert_eq(failures, ["lobby.no_crew", "lobby.no_crew"] as Array[String])
	assert_eq(UiText.text("lobby.no_crew"), "No crew with that code")
	assert_eq(bo.state, LobbyService.State.IDLE)
	assert_eq(bo.backend.lobby_id, 0, "nothing joined")


func test_a_sixth_cannot_join() -> void:
	var rig: R.Rig = R.make(self)
	var host: LobbyService = rig.client("Ann")
	host.create()
	await rig.settle()
	var others: Array[LobbyService] = []
	for n: String in ["Bo", "Cat", "Dee", "Eli", "Fen"]:
		var c: LobbyService = rig.client(n)
		c.join_code(host.code)
		others.append(c)
		await rig.settle()
	for i: int in 4:
		assert_eq(others[i].state, LobbyService.State.IN_LOBBY, "member %d" % (i + 2))
	assert_eq(others[4].state, LobbyService.State.IDLE, "the sixth is refused")
	assert_eq(host.crew().size(), 5)


func test_another_build_is_refused() -> void:
	var rig: R.Rig = R.make(self)
	var ann: LobbyService = rig.client("Ann")
	ann.create()
	await rig.settle()
	ann.backend.set_data("lb_build", "an-older-build")
	await rig.settle()
	var bo: LobbyService = rig.client("Bo")
	var failures: Array[String] = []
	bo.failed.connect(func(k: String) -> void: failures.append(k))
	bo.join(ann.backend.lobby_id)  # an invite into another build
	await rig.settle()
	assert_eq(failures, ["lobby.different_version"] as Array[String])
	assert_eq(UiText.text("lobby.different_version"), "Different version")
	assert_eq(bo.backend.lobby_id, 0, "left at once")
	bo.join_code(ann.code)
	await rig.settle_retry()
	var last: String = failures.back()
	assert_eq(last, "lobby.no_crew", "searches filter on the build")


func test_release_builds_write_no_address_and_never_connect_by_it() -> void:
	var rig: R.Rig = R.make(self)
	var ann: LobbyService = rig.client("Ann", true)
	var connects: Array[String] = []
	ann.connect_requested.connect(func(a: String) -> void: connects.append(a))
	ann.create()
	await rig.settle()
	assert_eq(str(Variants.dict(Variants.dict(rig.server.lobbies[ann.backend.lobby_id])["data"])["lb_dev_addr"]), "")
	assert_eq(connects, [] as Array[String])


func test_streamer_mode_hides_the_code_and_names() -> void:
	var rig: R.Rig = R.make(self)
	var ann: LobbyService = rig.client("Ann")
	ann.create()
	await rig.settle()
	var bo: LobbyService = rig.client("Bo")
	bo.join_code(ann.code)
	await rig.settle()
	ann.steam.streamer_mode = true
	assert_eq(ann.shown_code(), "••••••")
	for m: Dictionary in ann.crew():
		assert_false(str(m["name"]) in ["Ann", "Bo"], "a lamp number, never a name: %s" % m["name"])
	assert_eq(str(ann.crew()[1]["name"]), "Lamp 2")


func test_leaving_and_the_shutdown_hook() -> void:
	var rig: R.Rig = R.make(self)
	var ann: LobbyService = rig.client("Ann")
	ann.create()
	await rig.settle()
	var bo: LobbyService = rig.client("Bo")
	bo.join_code(ann.code)
	await rig.settle()
	bo.steam.shutdown()  # quitting: hook 10 leaves the lobby first
	await rig.settle()
	assert_eq(bo.state, LobbyService.State.IDLE)
	assert_eq(ann.crew().size(), 1, "the host sees Bo gone")


func test_the_steam_backend_creates_invites_and_joins_on_request() -> void:
	var fake: SteamApi = Fake.new()
	var steam: SteamService = SteamService.new(fake)
	add_child_autofree(steam)
	steam.boot(false, false, "")
	var s: LobbyService = LobbyService.new(SteamLobbyBackend.new(fake), steam, false)
	add_child_autofree(s)
	s.server_address = "10.0.0.2:24600"
	s.create()
	assert_eq(s.state, LobbyService.State.IN_LOBBY)
	var lobbies: Dictionary = fake.get(&"lobbies")
	var host_lobby: int = s.backend.lobby_id
	var l: Dictionary = lobbies[host_lobby]
	assert_eq(Variants.whole(l["limit"]), 5)
	assert_eq(str(Variants.dict(l["data"])["lb_code"]), s.code)
	assert_true(s.invite(), "the overlay's invite dialog")
	assert_eq(Variants.whole(fake.get(&"invites_opened")), 1)
	# Another lobby, joined by an accepted invite ("Join Game" arrives the same way).
	var other: int = Variants.whole(fake.call(&"add_lobby", 76561198000000777, {"lb_game": "lampblack", "lb_build": Protocol.build_id(),
		"lb_proto": str(Protocol.PROTOCOL_VERSION), "lb_dev_addr": "10.0.0.9:24600", "lb_code": "QQ22RR"}))
	var connects: Array[String] = []
	s.connect_requested.connect(func(a: String) -> void: connects.append(a))
	fake.call(&"request_join", other)
	assert_eq(s.backend.lobby_id, other, "left the old lobby and joined the invited one")
	assert_eq(connects, ["10.0.0.9:24600"] as Array[String])
	var off: SteamApi = Fake.new()
	off.set(&"overlay_on", false)
	var steam2: SteamService = SteamService.new(off)
	add_child_autofree(steam2)
	steam2.boot(false, false, "")
	var s2: LobbyService = LobbyService.new(SteamLobbyBackend.new(off), steam2, false)
	add_child_autofree(s2)
	s2.create()
	assert_false(s2.invite(), "the overlay disabled: no invite dialog; the screen offers the code")
