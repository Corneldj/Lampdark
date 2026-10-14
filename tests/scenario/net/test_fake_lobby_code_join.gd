extends GutTest
## STM-02: two clients create a lobby, join by code and ready up through FakeLobbyBackend and the
## dev server's rendezvous; the host leaving hands the lobby on (as Steam does) and the rendezvous
## forgets an empty lobby.

const R = preload("res://tests/unit/client/net/steam/lobby_rig.gd")


func before_all() -> void:
	assert_true(Tuning.load_client())


func test_create_join_by_code_and_ready() -> void:
	var rig: R.Rig = R.make(self)
	var host: LobbyService = rig.client("Ann")
	var guest: LobbyService = rig.client("Bo")
	host.create()
	await rig.settle()
	assert_eq(host.code.length(), 6)
	guest.join_code(host.code.to_lower())
	await rig.settle()
	assert_eq(guest.backend.lobby_id, host.backend.lobby_id)
	host.set_ready(true)
	guest.set_ready(true)
	await rig.settle()
	for s: LobbyService in [host, guest]:
		var crew: Array[Dictionary] = s.crew()
		assert_eq(crew.size(), 2)
		for m: Dictionary in crew:
			assert_true(Variants.flag(m["ready"]), "%s sees everyone ready" % s.steam.persona_name())
	host.start()
	await rig.settle()
	assert_eq(guest.backend.data("lb_state"), LobbyMetadata.RUNNING, "the host's Go down reaches the crew")
	host.leave()
	await rig.settle()
	assert_eq(guest.backend.owner(), guest.backend.self_id(), "the lobby passes to Bo")
	guest.leave()
	await rig.settle()
	assert_true(rig.server.lobbies.is_empty(), "an empty lobby is gone")


func test_a_dropped_member_leaves_the_lobby() -> void:
	var rig: R.Rig = R.make(self)
	var host: LobbyService = rig.client("Ann")
	var guest: LobbyService = rig.client("Bo")
	host.create()
	await rig.settle()
	guest.join_code(host.code)
	await rig.settle()
	(guest.backend as FakeLobbyBackend).close()
	await rig.settle()
	assert_eq(host.crew().size(), 1, "a dropped connection leaves the lobby")


func test_release_servers_never_start_the_rendezvous() -> void:
	var src: String = FileAccess.get_file_as_string("res://server/server_main.gd")
	assert_true(src.contains("\tif not config.build.is_release() and not hosted:\n\t\t_start_rendezvous(bind_address, transport.bound_port())"),
		"dev, QA and kill-test servers only (and never a private host's: its friends come through Steam)")
	assert_eq(src.count("LobbyRendezvous.new("), 1)


func test_the_server_seats_no_more_than_the_lobby_holds() -> void:
	# NET-02's test_full_server_refuses proves a full server refuses the next HELLO with FULL; the
	# game server's slots are the lobby's limit, so a sixth player is refused there too.
	var src: String = FileAccess.get_file_as_string("res://server/server_main.gd")
	assert_true(src.contains("var slots: int = Tuning.i(&\"modes.friends_lobby_max\")"))
	assert_true(src.contains("net = ServerNet.new(game_transport, slots)"))
	assert_eq(Tuning.i(&"modes.friends_lobby_max"), 5)
	assert_eq(LobbyService.limit(), 5, "the lobby and the server agree")
