extends GutTest
## MOD-03 (Gameplay §12.6): a fresh seed for every run, so no two runs share a mine: 10,000 run
## creations draw 10,000 distinct seeds.


func test_ten_thousand_runs_ten_thousand_seeds() -> void:
	var seen: Dictionary = {}
	for i: int in 10000:
		seen[RunSetup.new_seed()] = true
	assert_eq(seen.size(), 10000)
	assert_false(seen.has(0), "never the zero seed")
