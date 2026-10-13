extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-02's guard queries: the right answer on fixture cases around each limit, and no search
## past it (Moth 30, Tapper rock 21, Stythe dark 21; 2,000 nodes at most).

const N = preload("res://tests/unit/creatures/nav_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_moth_around_30() -> void:
	var s: Scenario = make({"seed": 7, "fixture": FixtureMap.from_ascii(N.road(40))})
	var nav: CreatureNav = s.run.creatures.nav
	var cases: int = 0
	for len: int in [28, 29, 30, 31, 32, 30, 29, 31]:
		var miner: Vector2 = Vector2(1 + len, 2) + Vector2(0.5, 0.5)
		assert_eq(nav.moth_path_within(Vector2i(1, 2), miner), len <= 30, "Moth at %d tiles" % len)
		cases += 1
	var past: Dictionary = s.run.creatures.nav.native.moth_path_within(Vector2i(1, 2), Vector2(35.5, 2.5), 30.0, 2000)
	assert_true(Variants.flag(past["hit_limit"]), "stops once past 30")
	assert_lt(int(Variants.number(past["expansions"])), 40, "and searched no further")
	assert_eq(cases, 8)


func test_stythe_around_21() -> void:
	var s: Scenario = make({"seed": 8, "fixture": FixtureMap.from_ascii(N.road(40))})
	var nav: CreatureNav = s.run.creatures.nav
	# The miner stands 1.5 tiles past the goal tile, so the path is (len) tiles to a tile within reach.
	for len: int in [19, 20, 21, 22, 23, 21]:
		var miner: Vector2 = Vector2(1 + len, 2) + Vector2(0.5, 0.5)
		assert_eq(nav.stythe_dark_path_within(Vector2i(1, 2), miner + Vector2(1.0, 0.0)), len <= 21, "Stythe at %d tiles" % len)


func test_tapper_around_21() -> void:
	# A thick rock band under a road along row 2: the Tapper starts in the rock at (1, 6); the miner
	# walks the road. The nearest usable face to a miner at x is the rock under them, row 3.
	var rows: PackedStringArray = N.road(40)
	rows.append("#".repeat(42))
	rows.append("#".repeat(42))
	rows.append("#".repeat(42))
	var s: Scenario = make({"seed": 9, "fixture": FixtureMap.from_ascii(rows)})
	var nav: CreatureNav = s.run.creatures.nav
	for x: int in [16, 17, 18, 19, 20, 21]:
		var miner: Vector2 = Vector2(x + 0.5, 2.5)
		var d: Dictionary = nav.native.tapper_rock_path_within(Vector2i(1, 6), miner, 200.0, 1.5)
		var cost: float = Variants.number(d["cost"])
		assert_eq(nav.tapper_rock_path_within(Vector2i(1, 6), miner), cost <= 21.0 + 1e-6, "Tapper path %.2f tiles" % cost)
	assert_true(nav.tapper_rock_path_within(Vector2i(1, 6), Vector2(16.5, 2.5)))
	assert_false(nav.tapper_rock_path_within(Vector2i(1, 6), Vector2(30.5, 2.5)))
