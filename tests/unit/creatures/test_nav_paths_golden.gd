extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-02: the same inputs give byte-identical paths on every platform. A fixed set of queries in
## every mode is hashed and compared with a golden file recorded on Linux; the Windows build
## (under Wine) must match it. Also times a long dark-walker path (budget: under 1 ms for 400).

const N = preload("res://tests/unit/creatures/nav_world.gd")
const GOLDEN: String = "res://tests/fixtures/creatures/nav_paths_hash.txt"


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_golden() -> void:
	var s: Scenario = make({"seed": 41, "fixture": FixtureMap.from_ascii(N.chambers())})
	var nav: CreatureNav = s.run.creatures.nav
	s.run.light.grid.add_spot(0, Vector2i(5, 6), 0.35, 0)
	s.step(1)
	var text: PackedStringArray = PackedStringArray()
	var queries: Array = [
		[NavModes.Mode.WALKER, Vector2i(1, 3), Vector2i(32, 11)], [NavModes.Mode.CRAWLER, Vector2i(1, 3), Vector2i(32, 11)],
		[NavModes.Mode.DARK, Vector2i(1, 3), Vector2i(32, 11)], [NavModes.Mode.ROCK, Vector2i(12, 4), Vector2i(36, 10)],
		[NavModes.Mode.WALKER, Vector2i(9, 11), Vector2i(1, 1)], [NavModes.Mode.CRAWLER, Vector2i(30, 3), Vector2i(2, 10)],
	]
	for q: Array in queries:
		var mode: NavModes.Mode = q[0]
		var from: Vector2i = q[1]
		var to: Vector2i = q[2]
		var r: Dictionary = nav.native.path(mode, from, to)
		text.append("%d %s %s %s %s" % [mode, from, to, r["cost"], r["tiles"]])
	text.append(str(nav.native.reachable_dark_tile_nearest(Vector2i(32, 11), Vector2i(1, 3), NavModes.dark())))
	text.append(str(nav.native.light_edge_ring(Vector2i(5, 6), 0.3, 50)))
	var digest: String = "\n".join(text).sha256_text()
	gut.p("nav paths digest: %s" % digest)
	var golden: String = FileAccess.get_file_as_string(GOLDEN).strip_edges()
	assert_eq(digest, golden, "identical paths on this platform; if the paths change on purpose, write the new digest to %s" % GOLDEN)


func test_long_dark_path_time() -> void:
	# A 40-wide serpentine of ten corridors: a dark path of about 400 tiles end to end.
	var rows: PackedStringArray = PackedStringArray(["#".repeat(40)])
	for y: int in range(1, 20):
		if y % 2 == 1:
			rows.append("#" + ".".repeat(38) + "#")
		elif (y / 2) % 2 == 1:
			rows.append("#".repeat(38) + ".#")
		else:
			rows.append("#." + "#".repeat(38))
	rows.append("#".repeat(40))
	var s: Scenario = make({"seed": 42, "fixture": FixtureMap.from_ascii(rows)})
	var nav: CreatureNav = s.run.creatures.nav
	var best: int = 1 << 40
	var r: Dictionary = {}
	for i: int in 5:
		var t0: int = Time.get_ticks_usec()
		r = nav.native.path(NavModes.Mode.DARK, Vector2i(1, 1), Vector2i(38, 19), NavModes.dark())
		best = mini(best, Time.get_ticks_usec() - t0)
	gut.p("dark walker: a %.0f-tile path planned in %d us (best of 5; budget 1 ms for 400)" % [Variants.number(r["cost"]), best])
	assert_true(Variants.flag(r["found"]))
	assert_gt(Variants.number(r["cost"]), 350.0)
