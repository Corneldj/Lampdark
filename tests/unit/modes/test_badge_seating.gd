extends GutTest
## MOD-03 (GDD §14.1): living miners never share a cap badge. Two players who prefer the same badge
## get it in join order, the second taking the next free one; a player with no preference takes the
## first free; a dead miner's badge is free again; Hired Hands take only badges no living player
## wears; a player retaking their place keeps theirs; and the seated badge is the one the cues carry.

var _dead: Dictionary = {}


func before_all() -> void:
	assert_true(Tuning.load_server())


func _crew() -> CrewSeating:
	_dead = {}
	var crew: CrewSeating = CrewSeating.new()
	crew.is_dead = func(slot: int) -> bool: return _dead.has(slot)
	return crew


func _seat(crew: CrewSeating, identity: String, slot: int, preferred: int) -> CrewSeating.Seat:
	var hello: Protocol.Hello = Protocol.Hello.new()
	hello.identity = identity
	hello.preferred_badge = preferred
	var choice: Dictionary = crew.choose(identity, hello)
	assert_false(choice.has("reject"), "%s may sit" % identity)
	return crew.commit(slot, identity, hello, choice)


func test_two_players_who_prefer_one_badge_get_it_in_join_order() -> void:
	var crew: CrewSeating = _crew()
	assert_eq(_seat(crew, "ann", 0, 2).badge, 2, "Ann keeps her own")
	assert_eq(_seat(crew, "bob", 1, 2).badge, 3, "Bob prefers it too, and takes the next free one")
	assert_eq(_seat(crew, "cid", 2, 3).badge, 4, "3 is Bob's now")
	assert_eq(_seat(crew, "dot", 3, -1).badge, 0, "no preference: the first free")
	assert_eq(_seat(crew, "eve", 4, 4).badge, 5, "counting up past the worn ones")
	var worn: Array[int] = crew.worn_badges()
	worn.sort()
	assert_eq(worn, [0, 2, 3, 4, 5] as Array[int], "five living miners, five badges")
	assert_eq(RunSetup.BADGES, MinerCues.BADGE_NONE - 1, "six badges, as VIS-06's cues carry them")


func test_counting_round_from_the_last_badge() -> void:
	var crew: CrewSeating = _crew()
	_seat(crew, "ann", 0, 5)
	assert_eq(_seat(crew, "bob", 1, 5).badge, 0, "after brown, round to clear")


func test_a_dead_miners_badge_is_free_again() -> void:
	var crew: CrewSeating = _crew()
	_seat(crew, "ann", 0, 2)
	_dead[0] = true
	assert_eq(_seat(crew, "bob", 1, 2).badge, 2, "Ann is dead: her badge is Bob's to take")


func test_hands_take_only_badges_no_living_player_wears() -> void:
	var crew: CrewSeating = _crew()
	_seat(crew, "ann", 0, 0)
	_seat(crew, "bob", 1, 1)
	assert_eq(crew.badges_for_hands(3), [2, 3, 4] as Array[int])
	_dead[0] = true
	assert_eq(crew.badges_for_hands(3), [0, 2, 3] as Array[int], "a dead player's badge goes to a Hand")
	assert_eq(crew.badges_for_hands(6).size(), 5, "never Bob's")
	assert_false(crew.badges_for_hands(6).has(1))


func test_a_returning_player_keeps_their_badge() -> void:
	var crew: CrewSeating = _crew()
	_seat(crew, "ann", 0, 2)
	_seat(crew, "bob", 1, 4)
	var hello: Protocol.Hello = Protocol.Hello.new()
	hello.preferred_badge = 4
	var back: Dictionary = crew.choose("ann", hello)
	assert_eq(int(Variants.number(back["badge"])), 2, "Ann retakes her place with her own badge, not Bob's")
	assert_eq(crew.commit(0, "ann", hello, back).badge, 2)
	assert_eq(crew.seats.size(), 2, "no second seat for Ann")


func test_the_seated_badge_rides_the_cues() -> void:
	var hub: InProcessTransport.Hub = InProcessTransport.Hub.new()
	var run: RunState = RunState.create(11, ServerConfig.Mode.FRIENDS, false)
	var server: InProcessTransport = InProcessTransport.new(hub)
	assert_eq(server.listen("server", 1), OK)
	var net: ServerNet = ServerNet.new(server, 5)
	ServerSystems.install(run, net)
	var clients: Array[ClientConnection] = []
	for who: Array in [["ann", 3], ["bob", 3]]:
		var c: ClientConnection = ClientConnection.new(InProcessTransport.new(hub))
		c.identity = str(who[0])
		c.preferred_badge = int(Variants.number(who[1]))
		assert_true(c.start("server", 1))
		clients.append(c)
		for _i: int in 4:
			for k: ClientConnection in clients:
				k.poll()
			run.run_tick()
	for c: ClientConnection in clients:
		c.poll()
	assert_eq(clients[0].welcome.badge, 3, "the Welcome names Ann's badge")
	assert_eq(clients[1].welcome.badge, 4, "and Bob's, the next free one")
	assert_eq(int(Variants.number(run.replication.badge_of.call(clients[0].welcome.slot))), 3, "the cues carry the seated badge")
	assert_eq(int(Variants.number(run.replication.badge_of.call(clients[1].welcome.slot))), 4)
