extends "res://tests/scenario/kit/scenario_test.gd"
## MOD-08 (Gameplay §13.9): with no order a Hand follows the nearest conscious human by path, at
## 3-5 tiles once settled; it switches only to a human 5 or more tiles nearer (one 4 tiles nearer
## never draws it); it never follows a miner seated at the switchboard; and it copies its human's
## gait, running only when they run, never further in a tick than its gait allows.

const HW = preload("res://tests/unit/hands/hand_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_it_settles_three_to_five_tiles_from_its_human() -> void:
	var s: Scenario = make({"seed": 4811, "fixture": HW.road(50)})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = HW.human(s, "ann", a + Vector2i(4, 0), 0.0)
	var hand: int = HW.hand(s, a + Vector2i(30, 0))
	s.step(300)
	var lo: float = INF
	var hi: float = 0.0
	for _i: int in 200:
		s.step(1)
		var d: float = HW.path_tiles(s, hand, ann.entity_id)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	gut.p("settled at %.1f-%.1f tiles by path" % [lo, hi])
	assert_gte(lo, Tuning.f(&"hands.follow_min_tiles"), "never closer than 3 once settled")
	assert_lte(hi, Tuning.f(&"hands.follow_max_tiles"), "never further than 5")
	assert_eq(HW.h_of(s, hand).followed, ann.entity_id)


func test_a_human_four_tiles_nearer_never_draws_it() -> void:
	var s: Scenario = make({"seed": 4812, "fixture": HW.road(50)})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = HW.human(s, "ann", a, 0.0)
	var hand: int = HW.hand(s, a + Vector2i(18, 0))
	s.step(6)
	assert_eq(HW.h_of(s, hand).followed, ann.entity_id, "the nearest human")
	# Bob stands 4 tiles nearer by path, between them.
	var bob: MinerHandle = HW.human(s, "bob", HW.pos(s, hand).floor() as Vector2i - Vector2i(14, 0), 0.0)
	var switched: bool = false
	for _i: int in 300:
		s.step(1)
		switched = switched or HW.h_of(s, hand).followed == bob.entity_id
	assert_false(switched, "4 tiles nearer never draws it")


func test_a_human_five_tiles_nearer_draws_it() -> void:
	var s: Scenario = make({"seed": 4813, "fixture": HW.road(50)})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = HW.human(s, "ann", a, 0.0)
	var hand: int = HW.hand(s, a + Vector2i(24, 0))
	s.step(6)
	assert_eq(HW.h_of(s, hand).followed, ann.entity_id)
	var bob: MinerHandle = HW.human(s, "bob", HW.pos(s, hand).floor() as Vector2i + Vector2i(6, 0), 180.0)
	s.step(12)
	assert_eq(HW.h_of(s, hand).followed, bob.entity_id, "Bob is far more than 5 tiles nearer: it follows him")


func test_never_the_operator_at_the_switchboard() -> void:
	var s: Scenario = make({"seed": 4814, "fixture": HW.road(50)})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = HW.human(s, "ann", a + Vector2i(20, 0), 0.0)
	var bob: MinerHandle = HW.human(s, "bob", a, 0.0)
	s.run.closeups.open_for(s.run, ann.entity_id, CloseupKind.Kind.SWITCHBOARD, "test")
	var hand: int = HW.hand(s, a + Vector2i(23, 0))
	for _i: int in 60:
		s.step(1)
		assert_ne(HW.h_of(s, hand).followed, ann.entity_id, "never the seated operator")
	assert_eq(HW.h_of(s, hand).followed, bob.entity_id, "the next nearest human instead")


func test_it_copies_its_humans_gait() -> void:
	var s: Scenario = make({"seed": 4815, "fixture": HW.road(60)})
	var a: Vector2i = s.fixture.spot("a")
	var hand: int = HW.hand(s, a)
	var ann: MinerHandle = HW.human(s, "ann", a + Vector2i(3, 0), 0.0)
	s.step(5)
	var max_step: float = 0.0
	var ran: bool = false
	var prev: Vector2 = HW.pos(s, hand)
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.RUN, 40)
	for _i: int in 60:
		s.step(1)
		var m: MovementSystem.Miner = s.run.movement.miner(4)
		ran = ran or m.state.gait == MinerMotion.RUN
		var p: Vector2 = HW.pos(s, hand)
		max_step = maxf(max_step, p.distance_to(prev))
		prev = p
	assert_true(ran, "it runs as its human runs")
	var run_speed: float = MinerMotion.Params.from_tuning().run_speed
	assert_lte(max_step, run_speed / Tuning.f(&"net.tick_hz") + 1e-6, "never further in a tick than its gait allows")
	assert_eq(s.run.movement.miner(4).stamina.pool_ms, s.run.movement.miner(ann.slot).stamina.pool_ms,
		"its stamina mirrors hers")
