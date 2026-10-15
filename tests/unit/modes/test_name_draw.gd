extends GutTest
## MOD-01: no excluded name is ever drawn (100,000 draws over varied seeds, with an excluded name
## planted in the list for the test); draws are distinct and avoid the roster's names.


func before_all() -> void:
	assert_true(Tuning.load_client())


func test_never_an_excluded_name() -> void:
	var names: Array[Dictionary] = NameDrawer.period_names()
	# Plant: treat the first period name as excluded for this test, so the fuzz can fail.
	var planted: Dictionary = names[0]
	NameDrawer._excluded[NameDrawer.full(planted)] = true
	var draws: int = 0
	var hits: int = 0
	for seed_value: int in 25000:
		for n: Dictionary in NameDrawer.draw(seed_value * 7919 + 13, seed_value % 5, 4, [] as Array[String]):
			draws += 1
			if NameDrawer.is_excluded(n):
				hits += 1
	NameDrawer._excluded.erase(NameDrawer.full(planted))
	assert_eq(draws, 100000)
	assert_eq(hits, 0, "no excluded name in 100,000 draws")


func test_distinct_and_avoiding_the_roster() -> void:
	var taken: Array[String] = []
	for n: Dictionary in NameDrawer.draw(5, 0, 20, [] as Array[String]).slice(0, 5):
		taken.append(NameDrawer.full(n))
	var drawn: Array[Dictionary] = NameDrawer.draw(5, 9, 50, taken)
	var seen: Dictionary = {}
	for n: Dictionary in drawn:
		assert_false(taken.has(NameDrawer.full(n)), "not a name the roster holds")
		assert_false(seen.has(NameDrawer.full(n)), "without replacement")
		seen[NameDrawer.full(n)] = true
	assert_eq(NameDrawer.draw(77, 3, 3, [] as Array[String]), NameDrawer.draw(77, 3, 3, [] as Array[String]), "the profile's stream replays")
