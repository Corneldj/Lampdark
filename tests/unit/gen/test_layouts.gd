extends GutTest
## GEN-05 from the server's side: base camp's gates are open sockets and its blind side shut for
## every seed; cells derived around base camp from a pack fit their sockets on both sides of every
## edge and stitch into one Road Graph with base camp; a derive is the same twice, cached or not;
## and MineLayouts loads the run's pack from data.


func before_all() -> void:
	assert_true(Tuning.load_server())


const Specs = preload("res://tests/unit/gen/template_specs.gd")


static func fixture_pack() -> PackedByteArray:
	return Specs.pack([Specs.grid_spec("seam_grid_a", "biome_cell", "seam", 1.0), Specs.grid_spec("seam_grid_b", "biome_cell", "seam", 2.0),
		Specs.grid_spec("seam_plain", "fallback", "seam", 1.0)])


func _layouts(run_seed: int) -> LbLayouts:
	var layouts: LbLayouts = LbLayouts.new()
	assert_true(layouts.load_pack(fixture_pack()))
	layouts.configure(run_seed, {"open_probability": Tuning.f(&"mine.edge_open_probability"),
		"offsets": Tuning.list_i(&"mine.socket_offsets_tiles"), "widths": Tuning.list_i(&"mine.socket_widths_tiles"),
		"reroll_limit": roundi(Tuning.f(&"mine.validator_max_rerolls")), "biome": "seam"})
	var gates: Dictionary = Basecamp.gate_sockets(run_seed)
	for side: String in Basecamp.SIDES:
		layouts.force_socket(Vector2i.ZERO, side, Variants.dict(gates[side]))
	return layouts


func test_base_camp_gates_are_open_and_its_blind_side_shut_for_every_seed() -> void:
	var outward: Dictionary = {"north": Vector2i(0, -1), "east": Vector2i(1, 0), "south": Vector2i(0, 1), "west": Vector2i(-1, 0)}
	var opposite: Dictionary = {"north": "south", "east": "west", "south": "north", "west": "east"}
	var wrong: int = 0
	for i: int in 300:
		var run_seed: int = 1000003 * (i + 1)
		var layouts: LbLayouts = MineLayouts.for_run(run_seed)
		var blind: String = Basecamp.SIDES[Basecamp.blind_side(run_seed)]
		for side: String in Basecamp.SIDES:
			var s: Dictionary = layouts.socket(Vector2i.ZERO, side)
			var gate: bool = side != blind
			var ok: bool = Variants.flag(s["open"]) == gate and Variants.flag(s["forced"])
			if gate:
				ok = ok and int(Variants.number(s["offset"])) == 10 and int(Variants.number(s["width"])) == 3
			var other: Vector2i = outward[side]
			ok = ok and layouts.socket(other, str(opposite[side])) == s
			wrong += 0 if ok else 1
	assert_eq(wrong, 0, "every seed: three gates open, 3 wide at 10; the blind side shut; both sides agree")


func test_cells_round_base_camp_fit_their_sockets_and_stitch_into_one_graph() -> void:
	var run_seed: int = 20261016
	var layouts: LbLayouts = _layouts(run_seed)
	var mine: Mine = Mine.new()
	mine.native.commit(Basecamp.cell_data(run_seed))
	var derived: Dictionary = {}
	for y: int in range(-2, 3):
		for x: int in range(-2, 3):
			var l: Dictionary = layouts.derive(Vector2i(x, y), 0)
			assert_true(Variants.flag(l["ok"]), "cell (%d, %d) derives" % [x, y])
			derived[Vector2i(x, y)] = l
			if not Variants.flag(l["base_camp"]):
				var data: LbCellData = l["cell"]
				assert_true(mine.native.commit(data))
	assert_true(Variants.flag(Variants.dict(derived[Vector2i.ZERO])["base_camp"]))
	var graph: LbRoadGraph = LbRoadGraph.new()
	graph.attach(mine.native)
	for c: Variant in derived.keys():
		var at: Vector2i = c
		assert_true(graph.stitch(at), "cell %s stitches" % at)
	# Across every edge between two derived cells: floor on both sides exactly where the socket opens.
	var mismatched: int = 0
	var open_edges: int = 0
	for c: Variant in derived.keys():
		var cell: Vector2i = c
		for side: String in ["east", "south"]:
			var nb: Vector2i = cell + (Vector2i(1, 0) if side == "east" else Vector2i(0, 1))
			if not derived.has(nb):
				continue
			var s: Dictionary = Variants.dict(Variants.dict(Variants.dict(derived[cell])["sockets"])[side])
			var expect: Array[int] = []
			if Variants.flag(s["open"]):
				open_edges += 1
				var w: int = int(Variants.number(s["width"]))
				for i: int in w:
					expect.append(int(Variants.number(s["offset"])) - w / 2 + i)
			var here: Array[int] = []
			var there: Array[int] = []
			for i: int in 20:
				var a: Vector2i = cell * 20 + (Vector2i(19, i) if side == "east" else Vector2i(i, 19))
				var b: Vector2i = nb * 20 + (Vector2i(0, i) if side == "east" else Vector2i(i, 0))
				if mine.native.is_walkable(a, true):
					here.append(i)
				if mine.native.is_walkable(b, true):
					there.append(i)
			mismatched += 0 if here == expect and there == expect else 1
	assert_eq(mismatched, 0, "no road changes width at an edge, base camp's gates included")
	assert_gt(open_edges, 10)
	# Sound walks from a far cell to base camp's deck through the stitched edges.
	var deck: Rect2i = Basecamp.deck_rect(run_seed)
	var reached: int = 0
	for c: Variant in derived.keys():
		var cell: Vector2i = c
		if cell == Vector2i.ZERO:
			continue
		var start: Vector2i = cell * 20 + Vector2i(10, 10)
		if mine.native.is_walkable(start, true) and graph.path_cost(start, deck.position, LbRoadGraph.MODE_AIR, 100000.0) >= 0.0:
			reached += 1
	assert_gt(reached, 0, "the derived cells join base camp's Road Graph")


func test_a_derive_is_the_same_twice_cached_or_not() -> void:
	var layouts: LbLayouts = _layouts(77)
	var first: Array[int] = []
	for x: int in range(1, 30):
		first.append(Variants.whole(layouts.derive(Vector2i(x, -3), 0)["digest"]))
	layouts.set_caching(false)
	for x: int in range(1, 30):
		assert_eq(Variants.whole(layouts.derive(Vector2i(x, -3), 0)["digest"]), first[x - 1])
	layouts.set_caching(true)
	layouts.set_verify(true)
	for x: int in range(29, 0, -1):
		assert_eq(Variants.whole(layouts.derive(Vector2i(x, -3), 0)["digest"]), first[x - 1])
	assert_eq(layouts.verify_failures(), 0)
	assert_ne(Variants.whole(layouts.derive(Vector2i(5, 5), 1)["digest"]), 0, "a reroll derives too")


func test_mine_layouts_loads_the_runs_pack() -> void:
	var current: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string("res://data/templates/set.json")))
	var layouts: LbLayouts = MineLayouts.for_run(5)
	assert_not_null(layouts)
	assert_eq(layouts.set_version(), str(current["set_version"]))
	assert_eq(MineLayouts.for_run(5, str(current["set_version"])).set_version(), str(current["set_version"]))
	var gates: Dictionary = Basecamp.gate_sockets(5)
	var open: int = 0
	for side: String in Basecamp.SIDES:
		open += 1 if Variants.flag(Variants.dict(gates[side])["open"]) else 0
	assert_eq(open, 3)
