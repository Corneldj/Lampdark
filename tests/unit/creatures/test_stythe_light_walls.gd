extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-13: light is walls. The Stythe never ends a tick on a tile lit to its threshold unless that
## tile lit under it, and then it leaves at 3.5 tiles/s; it never passes a closed air door or a gate;
## its guard predicate is right on 20 fixture cases round 21 dark tiles.

const W = preload("res://tests/unit/creatures/stythe_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_pushed_off_light_never_onto_it() -> void:
	var s: Scenario = make({"seed": 1241, "fixture": W.road(60), "overrides": W.ON})
	var st: StytheCreature = W.stythe(s, Vector2i(30, 2))
	s.step(2)
	var start: Vector2i = st.tile(s.run)
	W.light(s, start, 0.5)
	W.light(s, start + Vector2i(1, 0), 0.5)
	var lit_under: Dictionary = {start: true}
	var last: Vector2 = st.position(s.run)
	var max_step: float = 0.0
	var on_lit: int = 0
	for _i: int in 40:
		s.step(1)
		var t: Vector2i = st.tile(s.run)
		if not st.unlit(s.run, t):
			assert_true(lit_under.has(t), "on a lit tile only where the light came to it, tick %d" % s.run.tick)
			on_lit += 1
		max_step = maxf(max_step, st.position(s.run).distance_to(last))
		last = st.position(s.run)
	assert_true(st.unlit(s.run, st.tile(s.run)), "off the light")
	assert_lte(on_lit, 4, "it left at once")
	assert_almost_eq(max_step, Tuning.f(&"stythe.speed") / 20.0, 0.01, "at 3.5 tiles/s")
	assert_lt(st.tile(s.run).x, start.x, "away from the lit side")


func test_never_through_a_shut_door_or_gate() -> void:
	for mark: String in ["D", "G"]:
		var rows: PackedStringArray = ["#".repeat(42), "#".repeat(42), "#" + ".".repeat(14) + mark + ".".repeat(25) + "#", "#".repeat(42), "#".repeat(42)]
		var s: Scenario = make({"seed": 1242, "fixture": FixtureMap.from_ascii(rows), "overrides": W.ON})
		var st: StytheCreature = W.stythe(s, Vector2i(5, 2))
		var ann: MinerHandle = W.miner(s, "ann", Vector2i(35, 2))
		s.step(2)
		var furthest: int = 0
		for _i: int in 300:
			st.chase(s.run, ann.entity_id)
			s.step(1)
			furthest = maxi(furthest, st.tile(s.run).x)
		assert_false(s.run.mine.native.is_walkable(Vector2i(15, 2), false), "%s still shut" % mark)
		assert_lt(furthest, 15, "never through the %s" % ("air door" if mark == "D" else "gate"))


func test_guard_predicate_round_21() -> void:
	var s: Scenario = make({"seed": 1243, "fixture": W.road(60), "overrides": W.ON})
	var st: StytheCreature = W.stythe(s, Vector2i(1, 2))
	s.step(1)
	var guard: Callable = st.guard_predicate()
	var cases: int = 0
	var miner: MinerHandle = W.miner(s, "m", Vector2i(40, 2))
	s.step(1)
	for len: int in [11, 15, 18, 19, 20, 21, 21, 22, 23, 24, 25, 30, 12, 16, 20, 21, 22, 26, 14, 28]:
		# The miner 1 tile past the path's end: within 1.5 of the tile `len` steps along.
		s.run.registry.get_entity(miner.entity_id).position = Vector2(2 + len, 2) + Vector2(0.5, 0.5)
		assert_eq(Variants.flag(guard.call(s.run, miner.entity_id)), len <= 21, "%d dark tiles" % len)
		cases += 1
	assert_eq(cases, 20)
	# A light across the road cuts the dark path: the guard fails short of 21.
	s.run.registry.get_entity(miner.entity_id).position = Vector2(12.5, 2.5)
	assert_true(Variants.flag(guard.call(s.run, miner.entity_id)), "10 dark tiles")
	W.light(s, Vector2i(6, 2), 0.5)
	s.step(1)
	assert_false(Variants.flag(guard.call(s.run, miner.entity_id)), "no dark path through light")
