extends GutTest
## GEN-02: the blind side from the seed's hash, each side 25% +/- 1.5% over 10,000 seeds;
## fixture lookup.


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_distribution() -> void:
	var counts: Array[int] = [0, 0, 0, 0]
	for seed_value: int in 10000:
		counts[Basecamp.blind_side(seed_value * 7919 + 13)] += 1
	gut.p("blind side over 10,000 seeds (N, E, S, W): %s" % [counts])
	for c: int in counts:
		assert_between(c / 10000.0, 0.235, 0.265)
	assert_eq(Basecamp.blind_side(42), Basecamp.blind_side(42), "the same seed, the same side")


func test_fixture_lookup() -> void:
	var seed_value: int = 1234
	var side: int = Basecamp.blind_side(seed_value)
	var hook: Array[Dictionary] = Basecamp.fixture(seed_value, "lamp_hook")
	assert_eq(hook.size(), 1)
	assert_eq(hook, Basecamp.fixture(seed_value, "lamp_hook", side), "the seed's rotation")
	assert_eq(Basecamp.fixture(seed_value, "no_such_thing").size(), 0)
