extends GutTest
## MOD-03 (Gameplay §13.2): no run seats two miners with one lamp number. A joiner offers their
## miners in the order they would play them; when the first's number is seated, the next of their
## three sits instead, and one whose three all clash is refused in plain words (Reject.LAMP_NUMBERS),
## before any game data. A dead miner's number stays taken. A Hello that is not a roster's (four
## miners, a number that is not three digits) is a bad message. The Welcome names the seated miner,
## the hello and welcome carry the seat exactly, and the seats survive a save.

var hub: InProcessTransport.Hub
var run: RunState
var net: ServerNet


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	hub = InProcessTransport.Hub.new()
	run = RunState.create(7, ServerConfig.Mode.FRIENDS, false)
	var server: InProcessTransport = InProcessTransport.new(hub)
	assert_eq(server.listen("server", 1), OK)
	net = ServerNet.new(server, 5)
	ServerSystems.install(run, net)


static func _miner(id: int, lamp: int, name: String) -> Dictionary:
	return {"id": id, "name": name, "lamp_number": lamp, "voice_id": id % 8, "book_pages": [] as Array[String]}


func _client(identity: String, offered: Array[Dictionary]) -> ClientConnection:
	var c: ClientConnection = ClientConnection.new(InProcessTransport.new(hub))
	c.identity = identity
	c.candidates = offered
	assert_true(c.start("server", 1))
	return c


func _settle(clients: Array[ClientConnection], ticks: int = 6) -> void:
	for _i: int in ticks:
		for c: ClientConnection in clients:
			c.poll()
		run.run_tick()
	for c: ClientConnection in clients:
		c.poll()


func test_a_clashing_joiner_sits_their_next_miner_and_three_clashes_are_refused() -> void:
	var ann: ClientConnection = _client("ann", [_miner(1, 114, "Ada Rowe")] as Array[Dictionary])
	_settle([ann])
	assert_eq(ann.state, ClientConnection.State.CONNECTED)
	assert_eq(ann.welcome.seated_miner, 1, "the Welcome names the seated miner")
	var bob: ClientConnection = _client("bob", [_miner(1, 114, "Harry Gibson"), _miner(2, 215, "Wilf Dodd"),
		_miner(3, 316, "Nell Shaw")] as Array[Dictionary])
	_settle([ann, bob])
	assert_eq(bob.state, ClientConnection.State.CONNECTED)
	assert_eq(bob.welcome.seated_miner, 2, "114 is Ada's: Bob's next miner sits")
	assert_eq(net.crew.of_slot(bob.welcome.slot).lamp_number, 215)
	assert_eq(net.crew.of_slot(bob.welcome.slot).name, "Wilf Dodd")
	var cid: ClientConnection = _client("cid", [_miner(7, 114, "Ellis Ward"), _miner(8, 215, "Ruth Hale"),
		_miner(9, 114, "Tom Pike")] as Array[Dictionary])
	_settle([ann, bob, cid], 10)
	assert_eq(cid.state, ClientConnection.State.REJECTED, "all three clash")
	assert_eq(cid.reject_reason, Protocol.Reject.LAMP_NUMBERS)
	assert_false(RejectText.text(cid.reject_reason).is_empty(), "refused in plain words")
	assert_eq(cid.frames_received, 0, "no game data before the refusal")
	assert_eq(cid.early_messages, 0, "nothing but the Reject")
	assert_eq(net.sessions.welcomed().size(), 2, "the refused joiner took no place")


func test_a_dead_miners_number_stays_taken() -> void:
	var crew: CrewSeating = CrewSeating.new()
	crew.is_dead = func(_slot: int) -> bool: return true
	var hello: Protocol.Hello = Protocol.Hello.new()
	hello.candidates = [_miner(1, 114, "Ada Rowe")] as Array[Dictionary]
	crew.commit(0, "ann", hello, crew.choose("ann", hello))
	var later: Protocol.Hello = Protocol.Hello.new()
	later.candidates = [_miner(4, 114, "Bert Lowe")] as Array[Dictionary]
	assert_eq(crew.choose("bob", later), {"reject": Protocol.Reject.LAMP_NUMBERS}, "Lamp 114 is Ada's, dead or not")


func test_a_place_left_at_the_pithead_frees_its_number() -> void:
	var crew: CrewSeating = CrewSeating.new()
	var hello: Protocol.Hello = Protocol.Hello.new()
	hello.candidates = [_miner(1, 114, "Ada Rowe")] as Array[Dictionary]
	crew.commit(0, "ann", hello, crew.choose("ann", hello))
	crew.release_slot(0)
	var bob: Protocol.Hello = Protocol.Hello.new()
	bob.candidates = [_miner(4, 114, "Bert Lowe")] as Array[Dictionary]
	var sits: Dictionary = Variants.dict(crew.choose("bob", bob)["miner"])
	assert_eq(int(Variants.number(sits["lamp_number"])), 114, "Ann left before the run began")


func test_a_hello_that_is_no_roster_is_a_bad_message() -> void:
	# The client never sends more than a roster's three; a crafted Hello does. The count byte follows
	# the fields every Hello has (it is the third byte from the end of one offering none).
	var none: Protocol.Hello = Protocol.Hello.new()
	var bare: PackedByteArray = Protocol.unframe(none.encode())["payload"]
	var count_at: int = bare.size() - 3
	var three: Protocol.Hello = Protocol.Hello.new()
	three.candidates = [_miner(1, 101, "Ada Rowe"), _miner(2, 102, "Wilf Dodd"), _miner(3, 103, "Nell Shaw"),
		_miner(4, 104, "Tom Pike")] as Array[Dictionary]
	var bytes: PackedByteArray = Protocol.unframe(three.encode())["payload"]
	assert_eq(Protocol.Hello.decode(bytes).candidates.size(), 3, "encode sends three at most")
	assert_eq(bytes[count_at], 3)
	bytes[count_at] = 4
	assert_true(Protocol.Hello.decode(bytes).malformed, "four candidates is no roster")
	var short: ClientConnection = _client("short", [_miner(1, 42, "Ada Rowe")] as Array[Dictionary])
	_settle([short])
	assert_eq(short.state, ClientConnection.State.REJECTED)
	assert_eq(short.reject_reason, Protocol.Reject.BAD_MESSAGE, "42 is not a three-digit lamp number")


func test_a_client_without_a_profile_sits_with_no_miner() -> void:
	var bot: ClientConnection = _client("bot", [] as Array[Dictionary])
	_settle([bot])
	assert_eq(bot.state, ClientConnection.State.CONNECTED)
	assert_eq(bot.welcome.seated_miner, -1)
	assert_eq(net.crew.identity_of(bot.welcome.slot), {}, "no name for LFT-11's record")


func test_the_hello_and_welcome_carry_the_seat_exactly() -> void:
	var h: Protocol.Hello = Protocol.Hello.new()
	h.identity = "76561198000000001"
	h.candidates = [_miner(3, 316, "Nell Shaw"), _miner(5, 517, "Wilf Dodd")] as Array[Dictionary]
	h.candidates[0]["book_pages"] = ["moth", "tapper"] as Array[String]
	h.preferred_badge = 4
	h.new_brigade_runs = 2
	var hello_bytes: PackedByteArray = Protocol.unframe(h.encode())["payload"]
	var back: Protocol.Hello = Protocol.Hello.decode(hello_bytes)
	assert_false(back.malformed)
	assert_eq(back.candidates.size(), 2)
	assert_eq(str(back.candidates[0]["name"]), "Nell Shaw")
	assert_eq(int(Variants.number(back.candidates[0]["lamp_number"])), 316)
	assert_eq(int(Variants.number(back.candidates[1]["voice_id"])), 5)
	assert_eq(Variants.array(back.candidates[0]["book_pages"]), ["moth", "tapper"])
	assert_eq(back.preferred_badge, 4)
	assert_eq(back.new_brigade_runs, 2)
	var w: Protocol.Welcome = Protocol.Welcome.new()
	w.seated_miner = 3
	w.badge = 4
	w.run_uuid = "c0ffee00-0000-4000-8000-000000000001"
	var welcome_bytes: PackedByteArray = Protocol.unframe(w.encode())["payload"]
	var wb: Protocol.Welcome = Protocol.Welcome.decode(welcome_bytes)
	assert_eq([wb.seated_miner, wb.badge, wb.run_uuid], [3, 4, w.run_uuid])
	assert_eq(wb.encode(), w.encode(), "byte for byte")


func test_the_seats_survive_a_save() -> void:
	var ann: ClientConnection = _client("ann", [_miner(1, 114, "Ada Rowe")] as Array[Dictionary])
	var bob: ClientConnection = _client("bob", [_miner(2, 215, "Wilf Dodd")] as Array[Dictionary])
	_settle([ann, bob])
	var saved: Dictionary = net.crew.to_dict()
	var again: CrewSeating = CrewSeating.new()
	again.from_dict(saved)
	assert_eq(again.to_dict(), saved)
	assert_eq(again.seated_numbers(), net.crew.seated_numbers())
	assert_eq(again.of_slot(bob.welcome.slot).name, "Wilf Dodd")
	var cid: Protocol.Hello = Protocol.Hello.new()
	cid.candidates = [_miner(9, 215, "Tom Pike")] as Array[Dictionary]
	assert_eq(again.choose("cid", cid), {"reject": Protocol.Reject.LAMP_NUMBERS}, "a resumed run still holds Lamp 215")
