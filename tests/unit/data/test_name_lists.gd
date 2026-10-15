extends GutTest
## MOD-01 (Gameplay §13.2, A.10; GDD §2.6): the period list holds about 400 names (380-420,
## Proposed), none twice and none excluded; the women's share is reported.


func before_all() -> void:
	assert_true(Tuning.load_client())


func test_the_lists() -> void:
	var names: Array[Dictionary] = NameDrawer.period_names()
	assert_between(names.size(), 380, 420, "about 400 period names")
	var seen: Dictionary = {}
	var women: int = 0
	for n: Dictionary in names:
		var full: String = NameDrawer.full(n)
		assert_false(seen.has(full), "no name twice: %s" % full)
		seen[full] = true
		assert_false(NameDrawer.is_excluded(n), "%s is on the exclusion list" % full)
		assert_false(str(n.get("given", "")).is_empty() or str(n.get("surname", "")).is_empty())
		women += 1 if Variants.flag(n.get("woman", false)) else 0
	var excluded: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(NameDrawer.EXCLUDED)))
	assert_eq(Variants.array(excluded["names"]).size(), 61, "the 61 of the Breath")
	gut.p("period names: %d, women's %d (%.0f%%)" % [names.size(), women, 100.0 * women / names.size()])
	assert_gt(women, 0, "women's among them")
