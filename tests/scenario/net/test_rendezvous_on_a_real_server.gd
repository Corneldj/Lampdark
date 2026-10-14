extends GutTest
## STM-02: a real dev server process starts the lobby rendezvous beside its game port; two dev-mode
## clients reach it over ENet, one opens a crew and the other joins by its code.

var _pid: int = -1


func before_all() -> void:
	assert_true(Tuning.load_client())


func after_all() -> void:
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)


func test_create_and_join_by_code_over_enet() -> void:
	var port: int = 26000 + randi() % 2000
	var args: PackedStringArray = PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--",
		"--server", "--port", str(port), "--exit-after-ticks", "900"])
	_pid = OS.create_process(OS.get_executable_path(), args)
	assert_gt(_pid, 0, "the server process started")
	await get_tree().create_timer(3.0).timeout
	var services: Array[LobbyService] = []
	for persona: String in ["Ann", "Bo"]:
		var steam: SteamService = SteamService.new(SteamApi.new())
		add_child_autofree(steam)
		steam.boot(false, true, persona)
		var backend: FakeLobbyBackend = FakeLobbyBackend.new(EnetTransport.new(), steam.steam_id, persona)
		backend.aim("127.0.0.1", LobbyRendezvousWire.port_for(port))
		var s: LobbyService = LobbyService.new(backend, steam, false)
		s.server_address = "127.0.0.1:%d" % port
		add_child_autofree(s)
		services.append(s)
	services[0].create()
	var waited: int = 0
	while services[0].state != LobbyService.State.IN_LOBBY and waited < 600:
		await get_tree().process_frame
		waited += 1
	assert_eq(services[0].state, LobbyService.State.IN_LOBBY, "a crew opened on the real server")
	services[1].join_code(services[0].code)
	waited = 0
	while services[1].state != LobbyService.State.IN_LOBBY and waited < 600:
		await get_tree().process_frame
		waited += 1
	assert_eq(services[1].state, LobbyService.State.IN_LOBBY, "joined by code over ENet")
	await get_tree().create_timer(0.5).timeout
	assert_eq(services[0].crew().size(), 2)
	for s: LobbyService in services:
		s.leave()
		(s.backend as FakeLobbyBackend).close()
	OS.kill(_pid)
	_pid = -1
