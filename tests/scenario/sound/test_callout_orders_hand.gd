extends "res://tests/scenario/kit/scenario_test.gd"
## SND-11 for MOD-08: kept_fraction_at(callout, tile, listener) gives what a listener there keeps, by
## the same routing and seeded mask: it agrees with a real listener at that tile, and is 0 out of
## reach (a Hand beyond the band's range hears no order).

const N = preload("res://tests/scenario/net/net04_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_the_query_agrees_with_a_real_listener() -> void:
	var s: Scenario = make({"seed": 441, "fixture": N.road(40)})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var bob: MinerHandle = s.add_miner("bob", a + Vector2i(9, 0))
	s.step(3)
	var checked: int = 0
	for i: int in 6:
		var id: int = s.run.callouts.speak(s.run, ann.slot, "count_off", CalloutLines.TALK)
		assert_gt(id, 0)
		s.step(4)
		var real: CalloutRecord = bob.connection.callouts[bob.connection.callouts.size() - 1]
		var query: float = s.run.callouts.kept_fraction_at(id, a + Vector2i(9, 0), bob.slot)
		assert_almost_eq(query, real.kept_share(), 1e-9, "callout %d: the query matches the listener" % id)
		assert_eq(s.run.callouts.kept_fraction_at(id, a + Vector2i(20, 0), bob.slot), 0.0, "beyond 12 tiles: 0")
		checked += 1 if real.kept_share() < 1.0 else 0
		s.step(80)
	assert_gt(checked, 0, "at least one compared callout lost frames")
