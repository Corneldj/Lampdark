extends GutTest
## MOD-03 (GDD §13.8): a friend may join a friends run in progress. Into an empty place, they come to
## on base camp's floor (the crew that came down at the start stands on the cage deck); into a filler
## Hired Hand's place, their own miner takes the Hand's body where it stands, with its lamp and belt
## (Proposed), their own lamp check, and the Hand leaves. Each miner's check carries its seated lamp
## number, and nothing set at creation changes.

const MAP: String = "m1_greybox"

var hub: InProcessTransport.Hub
var run: RunState
var net: ServerNet
var mine: Mine
var arrival: M1Arrival
var clients: Array[ClientConnection] = []
## The filler Hand standing in a place (MOD-08's stand-in): entity -> still a Hand.
var hands: Dictionary = {}


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	hub = InProcessTransport.Hub.new()
	var t: InProcessTransport = InProcessTransport.new(hub)
	t.listen("s", 1)
	run = RunState.create(13, ServerConfig.Mode.FRIENDS, false)
	mine = Mine.new()
	assert_gt(FixedMapLoader.load_cells(mine, MAP), 0)
	net = ServerNet.new(t, 5)
	ServerSystems.install(run, net, mine)
	FixedMapLoader.populate(run, MAP, true, true)
	hands = {}
	run.crew.is_hired_hand = func(e: int) -> bool: return Variants.flag(hands.get(e, false))
	clients = []


func _join(identity: String, lamp: int) -> ClientConnection:
	var c: ClientConnection = ClientConnection.new(InProcessTransport.new(hub))
	c.identity = identity
	c.candidates = [{"id": 1, "name": "Ada Rowe" if identity == "ann" else "Wilf Dodd", "lamp_number": lamp, "voice_id": 1,
		"book_pages": []}] as Array[Dictionary]
	assert_true(c.start("s", 1))
	clients.append(c)
	for _i: int in 8:
		for k: ClientConnection in clients:
			k.poll()
		run.run_tick()
	assert_eq(c.state, ClientConnection.State.CONNECTED, "%s welcomed" % identity)
	return c


## The run begins with the crew seated (a hosted run's start, server_main's _begin_run).
func _begin() -> void:
	assert_eq(RunSetup.create(run, RunOptions.defaults(ServerConfig.Mode.FRIENDS), net.sessions.welcomed().size(),
		[9] as Array[int]), "")
	arrival = M1Arrival.new(run, mine, net.crew)
	arrival.hand_leaves = func(e: int) -> void: hands[e] = false
	net.welcomed.connect(arrival.on_welcomed)
	arrival.arrive_crew(net.sessions.welcomed())


func _tile_of(identity: String) -> Vector2i:
	return Vector2i(run.registry.get_entity(Variants.whole(arrival.miners[identity])).position.floor())


func test_an_empty_place_comes_to_on_base_camps_floor() -> void:
	_join("ann", 114)
	_begin()
	var deck: Rect2i = Basecamp.deck_rect(run.base_camp.seed_value, run.base_camp.side)
	assert_true(deck.has_point(_tile_of("ann")), "the crew came down in the cage")
	var staged: String = run.header.staging
	var jobs: Array[StringName] = run.repair.list.jobs.duplicate()
	var bob: ClientConnection = _join("bob", 215)
	assert_true(arrival.miners.has("bob"), "Bob's miner arrived")
	var at: Vector2i = _tile_of("bob")
	assert_true(run.base_camp.inside_tiles.has(at), "in base camp: %s" % at)
	assert_false(deck.has_point(at), "on base camp's floor, not the cage deck")
	var bob_miner: int = Variants.whole(arrival.miners["bob"])
	assert_eq(run.inventory.hands_of(bob_miner).lamp_check, 215, "his check carries his lamp number")
	assert_eq(run.inventory.hands_of(Variants.whole(arrival.miners["ann"])).lamp_check, 114)
	for _i: int in 4:
		bob.poll()
		run.run_tick()
	bob.poll()
	assert_false(bob.view.own.is_empty(), "Bob sees his own miner")
	assert_eq(run.header.staging, staged, "the staging never changes after creation")
	assert_eq(run.repair.list.jobs, jobs, "nor the list")
	assert_eq(run.header.humans_at_start, 1)


func test_a_filler_hands_place_is_taken_where_it_stands() -> void:
	_join("ann", 114)
	_begin()
	# A filler Hand holds the place in slot 1, out by the north gate, with a lamp and a spanner.
	var stands: Vector2 = Vector2(arrival.arrival_tiles()[arrival.arrival_tiles().size() - 1]) + Vector2(0.5, 0.5)
	var hand: SimEntity = run.registry.create(WorldIds.EntityKind.MINER, stands)
	run.movement.add_miner(1, hand.id, hand.position, 0)
	run.miner_state.add_miner(hand.id, 1)
	hands[hand.id] = true
	var w: ItemWorld = run.inventory.world
	assert_true(run.inventory.give(run, hand.id, w.make(ItemKinds.Kind.GAUZE_LAMP)))
	assert_true(run.inventory.give(run, hand.id, w.make(ItemKinds.Kind.SPANNER)))
	var kit: int = run.inventory.hands_of(hand.id).count_of(ItemKinds.Kind.GAUZE_LAMP) + run.inventory.hands_of(hand.id).count_of(ItemKinds.Kind.SPANNER)
	assert_eq(kit, 2)
	var entities: int = run.registry.ids().size()
	var bob: ClientConnection = _join("bob", 215)
	assert_eq(bob.welcome.slot, 1, "the Hand's place")
	assert_eq(Variants.whole(arrival.miners["bob"]), hand.id, "Bob's miner takes the Hand's body")
	assert_eq(run.registry.ids().size(), entities, "no second body")
	assert_false(Variants.flag(hands[hand.id]), "the Hand left")
	assert_lt(run.registry.get_entity(hand.id).position.distance_to(stands), 0.01, "where it stood")
	var belt: HandsAndBelt = run.inventory.hands_of(hand.id)
	assert_eq(belt.count_of(ItemKinds.Kind.GAUZE_LAMP), 1, "the Hand's lamp")
	assert_eq(belt.count_of(ItemKinds.Kind.SPANNER), 1, "and its belt")
	assert_eq(belt.lamp_check, 215, "with Bob's own lamp check")
	assert_eq(run.vision.watched_entity(1), hand.id, "Bob watches through it")
	for _i: int in 4:
		bob.poll()
		run.run_tick()
	bob.poll()
	assert_false(bob.view.own.is_empty(), "Bob sees it as his own miner")
