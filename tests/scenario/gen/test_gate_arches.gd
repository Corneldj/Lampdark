extends GutTest
## GEN-06: for 100 seeds the three cells base camp's gate roads enter are derived (pit-bottom
## roads, whichever template is chosen) and each gate road is brick-lined for exactly 10 tiles of
## path past its gate: GEN-02's check passes, and walking the arch from the gate reaches 10 tiles
## and no further.

const Specs = preload("res://tests/unit/gen/template_specs.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_every_gate_road_is_brick_lined_for_ten_tiles() -> void:
	var pack: PackedByteArray = Specs.pack([Specs.grid_spec("pit_bottom_grid_a", "biome_cell", "pit_bottom", 1.0),
		Specs.grid_spec("pit_bottom_grid_b", "biome_cell", "pit_bottom", 2.0), Specs.grid_spec("pit_bottom_plain", "fallback", "pit_bottom", 1.0)])
	var length: int = roundi(Tuning.f(&"basecamp.arch_length_tiles"))
	var failures: Array[String] = []
	var walked: int = 0
	for i: int in 100:
		var run_seed: int = 7919 * (i + 1)
		var layouts: LbLayouts = LbLayouts.new()
		assert_true(layouts.load_pack(pack))
		MineLayouts.configure(layouts, run_seed)
		var cells: Array[Vector2i] = MineLayouts.gate_cells(run_seed)
		if cells.size() != 3:
			failures.append("seed %d: %d gate cells" % [run_seed, cells.size()])
			continue
		for cell: Vector2i in cells:
			if layouts.biome_of(cell) != "pit_bottom":
				failures.append("seed %d: gate cell %s is %s" % [run_seed, cell, layouts.biome_of(cell)])
			var data: LbCellData = MineLayouts.cell_data(layouts, run_seed, cell)
			if data == null:
				failures.append("seed %d: gate cell %s derives nothing" % [run_seed, cell])
				continue
			var rows: PackedStringArray = CellFile.rows_of(data)
			var problems: Array[String] = Basecamp.check_gate_arches(run_seed, cell, rows)
			if not problems.is_empty():
				failures.append("seed %d cell %s: %s" % [run_seed, cell, problems[0]])
			var arch: Dictionary = Basecamp.arch_tiles(run_seed, cell, rows)
			var deepest: int = 0
			for t: Variant in arch.keys():
				deepest = maxi(deepest, int(Variants.number(arch[t])))
			if deepest != length:
				failures.append("seed %d cell %s: the arch walks %d tiles" % [run_seed, cell, deepest])
			walked += 1
	assert_eq(failures, [] as Array[String])
	assert_eq(walked, 300)
