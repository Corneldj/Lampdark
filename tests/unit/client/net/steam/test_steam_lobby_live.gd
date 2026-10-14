extends GutTest
## STM-02's live check against a running, signed-in Steam (manual, LB_STEAM_LIVE=1, from game/ where
## steam_appid.txt sits; pending otherwise and in CI): a real lobby on the app, every key written,
## the limit set, found again by its code through Steam's worldwide search, then left.


func before_all() -> void:
	assert_true(Tuning.load_client())


func test_a_real_lobby_round_trip() -> void:
	if OS.get_environment("LB_STEAM_LIVE") != "1":
		pending("manual: LB_STEAM_LIVE=1 with Steam running")
		return
	var api: SteamApi = SteamApi.new()
	var steam: SteamService = SteamService.new(api)
	add_child_autofree(steam)
	assert_eq(steam.boot(false, false, ""), SteamService.Boot.CONTINUE)
	assert_true(steam.available(), "Steam is up")
	var s: LobbyService = LobbyService.new(SteamLobbyBackend.new(api), steam, false)
	add_child_autofree(s)
	s.server_address = "127.0.0.1:24600"
	s.create()
	var waited: int = 0
	while s.state != LobbyService.State.IN_LOBBY and waited < 600:
		await get_tree().process_frame
		waited += 1
	assert_eq(s.state, LobbyService.State.IN_LOBBY, "a real lobby")
	var id: int = s.backend.lobby_id
	gut.p("lobby %d, code %s, members %s" % [id, s.code, s.backend.members()])
	assert_eq(s.backend.data("lb_code"), s.code)
	assert_eq(s.backend.data("lb_game"), "lampblack")
	assert_eq(s.backend.owner(), steam.steam_id)
	# A second service on the same account looks the code up as a friend would; Steam indexes the new
	# lobby's data within a couple of seconds, which the lookup's one retry covers.
	var finder: LobbyService = LobbyService.new(SteamLobbyBackend.new(api), steam, false)
	add_child_autofree(finder)
	var found: Array[PackedInt64Array] = []
	finder.backend.search_done.connect(func(ids: PackedInt64Array) -> void: found.append(ids))
	finder.state = LobbyService.State.IDLE
	finder.join_code(s.code.to_lower())
	waited = 0
	while finder.state == LobbyService.State.SEARCHING and waited < 1200:
		await get_tree().process_frame
		waited += 1
	gut.p("lookups: %s" % [found])
	assert_false(found.is_empty())
	var last: PackedInt64Array = found.back() if not found.is_empty() else PackedInt64Array()
	assert_true(last.has(id), "Steam finds the lobby by its code (lower case typed)")
	s.leave()
	steam.shutdown()
