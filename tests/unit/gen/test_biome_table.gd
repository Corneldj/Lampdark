extends GutTest
## GEN-06's ground-rule table from data: every biome has its socket widths and a template count;
## each ring's weights name only those biomes and add to 1; a run's deriver reads them, so cells
## deepen with the rings (pit-bottom roads by the shaft, the Old Men's Workings in the Deep, or the
## biome GEN-16's v1 override folds them into) and every opening takes a width both of its cells
## allow; a template's stubs keep to its biome's widths.

const Specs = preload("res://tests/unit/gen/template_specs.gd")
const BIOMES: Array[String] = ["pit_bottom", "seam", "old_workings", "black_seam", "old_mens"]


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_every_biome_has_widths_and_a_template_count() -> void:
	var lo: Dictionary = Tuning.table(&"mine.biome_socket_widths_min")
	var hi: Dictionary = Tuning.table(&"mine.biome_socket_widths_max")
	var counts: Dictionary = Tuning.table(&"mine.target_cell_templates_by_biome")
	for biome: String in BIOMES + ["main_road"]:
		assert_true(lo.has(biome) and hi.has(biome), "%s has socket widths" % biome)
		assert_lte(int(Variants.number(lo[biome])), int(Variants.number(hi[biome])))
		assert_gt(int(Variants.number(counts.get(biome, 0))), 0, "%s has a template count" % biome)
	var table: Dictionary = MineLayouts.biome_table()
	var rings: Array = table["rings"]
	assert_eq(rings.size(), 5, "rings 0 to 4")
	for ring: Variant in rings:
		var total: float = 0.0
		for pair: Variant in Variants.array(ring):
			var p: Array = Variants.array(pair)
			assert_true(BIOMES.has(str(p[0])), "%s is a biome" % p[0])
			total += float(Variants.number(p[1]))
		assert_almost_eq(total, 1.0, 1e-9)
	var bounds: Array[int] = table["ring_bounds"]
	assert_eq(bounds, [80, 200, 400, 700] as Array[int])


func test_cells_deepen_with_the_rings() -> void:
	var layouts: LbLayouts = MineLayouts.for_run(4242)
	assert_eq(layouts.biome_of(Vector2i.ZERO), "", "base camp is no biome")
	for c: Vector2i in [Vector2i(1, 0), Vector2i(-2, 1), Vector2i(0, 3)]:
		assert_eq(layouts.biome_of(c), "pit_bottom", "ring 0 (%s)" % c)
	# Until GEN-17 brings the deep biomes, mine.v1_deep_biome_override names the biome they take.
	var deep: String = Tuning.s(&"mine.v1_deep_biome_override") if Tuning.current.has_key(&"mine.v1_deep_biome_override") else "old_mens"
	for c: Vector2i in [Vector2i(40, 0), Vector2i(-40, 5), Vector2i(0, -45)]:
		assert_eq(layouts.biome_of(c), deep, "the Deep (%s)" % c)
	var ring1: Dictionary = {}
	for x: int in range(5, 9):
		for y: int in range(-2, 3):
			ring1[layouts.biome_of(Vector2i(x, y))] = true
	for b: Variant in ring1.keys():
		assert_true(["seam", "old_workings"].has(str(b)), "ring 1 is Seam or Old Workings")


func test_openings_take_widths_both_cells_allow() -> void:
	var layouts: LbLayouts = MineLayouts.for_run(77)
	var hi: Dictionary = Tuning.table(&"mine.biome_socket_widths_max")
	var lo: Dictionary = Tuning.table(&"mine.biome_socket_widths_min")
	var open: int = 0
	var wrong: int = 0
	for y: int in range(-45, 46, 3):
		for x: int in range(-45, 46, 3):
			var a: Vector2i = Vector2i(x, y)
			var b: Vector2i = a + Vector2i(1, 0)
			if a == Vector2i.ZERO or b == Vector2i.ZERO:
				continue
			var s: Dictionary = layouts.socket(a, "east")
			if not Variants.flag(s["open"]) or Variants.flag(s["forced"]):
				continue # main roads (GEN-07) are 3 wide whatever the biome
			open += 1
			var w: int = int(Variants.number(s["width"]))
			var ba: String = layouts.biome_of(a)
			var bb: String = layouts.biome_of(b)
			var in_a: bool = w >= int(Variants.number(lo[ba])) and w <= int(Variants.number(hi[ba]))
			var in_b: bool = w >= int(Variants.number(lo[bb])) and w <= int(Variants.number(hi[bb]))
			var narrower_widest: int = mini(int(Variants.number(hi[ba])), int(Variants.number(hi[bb])))
			if not ((in_a and in_b) or w == narrower_widest):
				wrong += 1
	assert_gt(open, 300)
	assert_eq(wrong, 0)


func test_a_templates_stubs_keep_to_its_biomes_widths() -> void:
	var problems: Array[String] = []
	Specs.pack([Specs.grid_spec("old_mens_grid", "biome_cell", "old_mens", 1.0, 3)], problems)
	assert_eq(problems.size(), 12, "each 3-wide stub in the Old Men's Workings (1 wide) is refused")
	if not problems.is_empty():
		assert_eq(problems[0], "template old_mens_grid: stubs: cell (0, 0) tile (5, 0): stub width 3 wider than the biome allows (1)")
	var fine: Array[String] = []
	Specs.pack([Specs.grid_spec("seam_grid", "biome_cell", "seam", 1.0)], fine)
	assert_eq(fine, [] as Array[String])
