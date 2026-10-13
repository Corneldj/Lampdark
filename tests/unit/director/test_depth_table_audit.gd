extends GutTest
## DIR-04's table audit: every cell of Gameplay §10.6's table, wherever its key lives, matches the
## design; the derived Tapper hearing for talk and a 40 np shot; Base camp in ring 0. Any drift
## fails the build.

## Gameplay §10.6, rings 0-4.
const DESIGN: Dictionary = {
	"pull factor D": [0.5, 1.0, 1.5, 2.0, 2.5],
	"tapper hearing": [0.8, 1.0, 1.2, 1.4, 1.6],
	"moth sight": [20, 25, 30, 35, 40],
	"stythe senses": [8, 10, 12, 14, 16],
	"stythe unheard mark": [60, 60, 45, 45, 45],
	"search time": [20, 20, 30, 40, 50],
	"moth frenzy": [60, 90, 90, 120, 150],
	"relax": [60, 60, 45, 30, 30],
}


func before_all() -> void:
	assert_true(Tuning.load_server())


func _value(column: String, ring: int) -> float:
	match column:
		"pull factor D":
			return Depth.pull_factor(ring)
		"tapper hearing":
			return CreatureTables.tapper_hearing_mult(ring)
		"moth sight":
			return CreatureTables.moth_sight_tiles(ring)
		"stythe senses":
			return CreatureTables.stythe_senses_tiles(ring)
		"stythe unheard mark":
			return CreatureTables.stythe_unheard_mark_s(ring)
		"search time":
			return CreatureTables.search_time_s(ring)
		"moth frenzy":
			return CreatureTables.moth_frenzy_s(ring)
		"relax":
			return Depth.relax_s(ring)
	return NAN


func test_every_cell() -> void:
	var cells: int = 0
	for column: String in DESIGN.keys():
		var want: Array = DESIGN[column]
		for ring: int in 5:
			assert_almost_eq(_value(column, ring), Variants.number(want[ring]), 1e-9, "%s, ring %d" % [column, ring])
			cells += 1
	assert_eq(cells, 40)


func test_ring_bounds() -> void:
	var bounds: Array[int] = Tuning.list_i(&"depth.ring_start_tiles")
	assert_eq(bounds, [80, 200, 400, 700] as Array[int], "0-79, 80-199, 200-399, 400-699, 700 and beyond")
	var centre: Vector2 = Vector2(WorldIds.SHAFT_CENTRE_X2, WorldIds.SHAFT_CENTRE_Y2) / 2.0
	for pair: Array in [[79.9, 0], [80.0, 1], [199.9, 1], [200.0, 2], [399.9, 2], [400.0, 3], [699.9, 3], [700.0, 4], [5000.0, 4]]:
		var d: float = pair[0]
		var want: int = pair[1]
		assert_eq(WorldCoords.ring_of_point(centre + Vector2(d, 0.0)), want, "%.1f tiles from the shaft" % d)
	assert_eq(WorldCoords.ring_of_tile(Vector2i(0, 0)), 0, "base camp, in cell (0, 0), is ring 0")
	assert_eq(WorldCoords.ring_of_tile(Vector2i(19, 19)), 0)


func test_derived_hearing() -> void:
	var talk: Array[float] = [6.4, 8.0, 9.6, 11.2, 12.8]
	for ring: int in 5:
		assert_almost_eq(CreatureTables.tapper_talk_hearing_tiles(ring), talk[ring], 1e-9, "talk, ring %d" % ring)
	assert_almost_eq(CreatureTables.tapper_hearing_tiles(1, 40.0), 36.0, 1e-9, "a 40 np shot in ring 1")
