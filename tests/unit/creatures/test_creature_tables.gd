extends GutTest
## CRT-01's tables (Gameplay §7.1): every ring and crew count.


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_per_ring() -> void:
	var rows: Dictionary = {
		"moth sight": [[20, 25, 30, 35, 40], func(r: int) -> float: return CreatureTables.moth_sight_tiles(r)],
		"moth frenzy": [[60, 90, 90, 120, 150], func(r: int) -> float: return CreatureTables.moth_frenzy_s(r)],
		"tapper hearing": [[0.8, 1.0, 1.2, 1.4, 1.6], func(r: int) -> float: return CreatureTables.tapper_hearing_mult(r)],
		"tapper talk": [[6.4, 8.0, 9.6, 11.2, 12.8], func(r: int) -> float: return CreatureTables.tapper_talk_hearing_tiles(r)],
		"stythe senses": [[8, 10, 12, 14, 16], func(r: int) -> float: return CreatureTables.stythe_senses_tiles(r)],
		"unheard mark": [[60, 60, 45, 45, 45], func(r: int) -> float: return CreatureTables.stythe_unheard_mark_s(r)],
		"search time": [[20, 20, 30, 40, 50], func(r: int) -> float: return CreatureTables.search_time_s(r)],
	}
	for row: String in rows.keys():
		var spec: Array = rows[row]
		var want: Array = spec[0]
		var lookup: Callable = spec[1]
		for r: int in 5:
			assert_almost_eq(Variants.number(lookup.call(r)), Variants.number(want[r]), 1e-9, "%s, ring %d" % [row, r])
	assert_eq(CreatureTables.moth_flare_sight_tiles(), 50.0)
	assert_eq(CreatureTables.moth_signal_sight_tiles(), 40.0)
	assert_eq(CreatureTables.stythe_senses_tiles(0, true), 20.0, "20 in its territory, any ring")


func test_per_crew() -> void:
	var rows: Dictionary = {
		"moth lights": [[3, 4, 5, 6, 7], func(n: int) -> float: return CreatureTables.moth_memory_lights(n)],
		"tapper heat": [[90, 90, 105, 120, 135], func(n: int) -> float: return CreatureTables.tapper_heat_window_s(n)],
		"tapper pause": [[3, 3, 3, 2, 2], func(n: int) -> float: return CreatureTables.tapper_listen_pause_s(n)],
		"stythe places": [[2, 3, 4, 5, 6], func(n: int) -> float: return CreatureTables.stythe_memory_places(n)],
		"stythe snuff": [[2.0, 2.0, 1.6, 1.6, 1.6], func(n: int) -> float: return CreatureTables.stythe_snuff_interval_s(n)],
	}
	for row: String in rows.keys():
		var spec: Array = rows[row]
		var want: Array = spec[0]
		var lookup: Callable = spec[1]
		for n: int in range(1, 6):
			assert_almost_eq(Variants.number(lookup.call(n)), Variants.number(want[n - 1]), 1e-9, "%s, crew %d" % [row, n])
	assert_eq(CreatureTables.stythe_snuff_interval_s(1, true), 1.6, "1.6 always in its territory")
	assert_eq(CreatureTables.moth_memory_lights(0), 3, "a crew count of 0 reads as 1")
	assert_eq(CreatureTables.moth_memory_lights(9), 7, "and above 5 as 5")
	assert_eq(CreatureTables.search_time_s(7), 50.0, "rings clamp to 0-4")
