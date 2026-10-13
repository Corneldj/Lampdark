extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-08's guard predicate: a rock path of 21 tiles or less to a usable face within 1.5 tiles of
## the miner, on fixture cases around 21.

const N = preload("res://tests/unit/creatures/nav_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_cases_around_21() -> void:
	var rows: PackedStringArray = N.road(40)
	for i: int in 3:
		rows.append("#".repeat(42))
	var s: Scenario = make({"seed": 2, "fixture": FixtureMap.from_ascii(rows)})
	s.place_creature(WorldIds.EntityKind.TAPPER, Vector2i(1, 6))
	var t: Tapper = s.run.creatures.creature_of_kind(WorldIds.EntityKind.TAPPER)
	var guard: Callable = t.guard_predicate()
	var cases: int = 0
	for x: int in range(10, 30):
		var miner: SimEntity = s.run.registry.create(WorldIds.EntityKind.MINER, Vector2(x + 0.5, 2.5))
		var d: Dictionary = s.run.creatures.nav.native.tapper_rock_path_within(t.tile(s.run), miner.position, 200.0, 1.5)
		var cost: float = Variants.number(d["cost"])
		assert_eq(Variants.flag(guard.call(s.run, miner.id)), cost <= 21.0 + 1e-6, "a rock path of %.2f tiles" % cost)
		s.run.registry.destroy(miner.id)
		cases += 1
	assert_eq(cases, 20)
