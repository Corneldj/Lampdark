extends RefCounted
## STM-02's test rig: the dev server's LobbyRendezvous and any number of dev-mode clients
## (SteamService in dev mode, FakeLobbyBackend, LobbyService), all on one in-process hub.

const HOST: String = "rendezvous"
const PORT: int = 24601


class Rig:
	extends RefCounted
	var test: GutTest
	var hub: InProcessTransport.Hub = InProcessTransport.Hub.new()
	var server: LobbyRendezvous
	var clients: Array[LobbyService] = []

	func client(persona: String, release: bool = false) -> LobbyService:
		var steam: SteamService = SteamService.new(SteamApi.new())
		test.add_child_autofree(steam)
		steam.boot(false, true, persona)
		var backend: FakeLobbyBackend = FakeLobbyBackend.new(InProcessTransport.new(hub), steam.steam_id, persona)
		backend.aim(HOST, PORT)
		var s: LobbyService = LobbyService.new(backend, steam, release)
		s.server_address = "127.0.0.1:24600"
		test.add_child_autofree(s)
		clients.append(s)
		return s

	## Runs the rendezvous and every client until messages settle.
	func settle(frames: int = 12) -> void:
		for _i: int in frames:
			server.poll()
			for c: LobbyService in clients:
				c.backend.poll()
			await test.get_tree().process_frame

	## Waits out a code lookup's one retry (net.invite_code_retry_s), then settles.
	func settle_retry() -> void:
		await settle()
		await test.get_tree().create_timer(Tuning.f(&"net.invite_code_retry_s") + 0.3).timeout
		await settle()


static func make(test: GutTest) -> Rig:
	var r: Rig = Rig.new()
	r.test = test
	var t: InProcessTransport = InProcessTransport.new(r.hub)
	t.listen(HOST, PORT)
	r.server = LobbyRendezvous.new(t)
	return r


## Scripts a service's next codes (clashes), then fresh ones.
static func force_codes(s: LobbyService, codes: Array[String]) -> void:
	var queue: Array[String] = codes.duplicate()
	s.next_code = func() -> String:
		return queue.pop_front() if not queue.is_empty() else InviteCode.generate()