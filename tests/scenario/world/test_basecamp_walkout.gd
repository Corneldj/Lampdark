extends "res://tests/scenario/kit/scenario_test.gd"
## GEN-02: a miner leaves by each gate; tiles inside, on the arches and beyond report the right
## material and inside flag, and the Road Graph stitches across the gates. Nothing of base camp's
## layout (anchors, the blind side) is ever named by client code.

const B = preload("res://tests/scenario/world/basecamp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _load(s: Scenario, seed_value: int) -> void:
	s.run.mine.native.unload(Vector2i(0, 0))
	s.run.mine.native.commit(Basecamp.cell_data(seed_value))
	for g: Dictionary in Basecamp.gate_specs(seed_value):
		var road: Array = B.road_cell(g)
		var cell: Vector2i = road[0]
		var raw_rows: PackedStringArray = road[1]
		var rows: PackedStringArray = Basecamp.apply_gate_arches(seed_value, cell, raw_rows)
		s.run.mine.native.commit(CellFile.from_dict(B.cell_file(cell, rows), "road"))


func test_walk_out_each_gate() -> void:
	var seed_value: int = 77
	for gi: int in 3:
		var s: Scenario = make({"seed": 200 + gi, "fixture": FixtureMap.from_ascii(PackedStringArray(["#"]))})
		_load(s, seed_value)
		assert_eq(s.run.road_graph.failed_cells, [] as Array[Vector2i], "every cell stitches")
		var g: Dictionary = Basecamp.gate_specs(seed_value)[gi]
		var outward: Vector2i = g["outward"]
		var gate_tiles: Array = g["tiles"]
		var mid: Vector2i = gate_tiles[1]
		var start: Vector2i = mid - outward * 3
		var ann: MinerHandle = s.add_miner("ann", start)
		var heading: float = fposmod(rad_to_deg(Vector2(outward).angle()), 360.0)
		ann.at(0).move(heading, InputRecord.Gait.WALK, 200)
		var seen: Dictionary = {"inside": 0, "arch": 0, "beyond": 0}
		var bad: Array[String] = []
		s.on_tick = func(sc: Scenario) -> void:
			var p: Vector2 = sc.run.registry.get_entity(ann.entity_id).position
			var t: Vector2i = Vector2i(floori(p.x), floori(p.y))
			var inside: bool = Basecamp.is_inside_base_camp(seed_value, t)
			var side_tile: Vector2i = t + Vector2i(outward.y, outward.x) * 2
			var wall: int = sc.run.mine.native.effective_material(side_tile)
			var rel: Vector2i = t - mid
			var along: int = rel.x * outward.x + rel.y * outward.y
			if inside:
				seen["inside"] += 1
			elif along >= 1 and along <= 10:
				seen["arch"] += 1
				if wall != WorldIds.TileMaterial.BRICK:
					bad.append("arch tile %s has a %d wall" % [t, wall])
			elif along > 11:
				seen["beyond"] += 1
				if wall != WorldIds.TileMaterial.ROCK:
					bad.append("beyond the arches at %s the wall is %d" % [t, wall])
		s.step(200)
		gut.p("gate %s: %s" % [g["side"], seen])
		assert_eq(bad, [] as Array[String])
		assert_gt(int(Variants.number(seen["inside"])), 0)
		assert_gt(int(Variants.number(seen["arch"])), 10, "walked the arches")
		assert_gt(int(Variants.number(seen["beyond"])), 5, "and past them")


func test_client_code_never_names_it() -> void:
	var pattern: RegEx = RegEx.create_from_string("Basecamp|blind_side|basecamp\\.")
	for dir: String in ["res://client", "res://shared/net"]:
		for f: String in DirAccess.get_files_at(dir):
			if f.ends_with(".gd"):
				for line: String in FileAccess.get_file_as_string(dir.path_join(f)).split("\n"):
					if not line.strip_edges().begins_with("#"):
						assert_null(pattern.search(line), "%s: %s" % [f, line.strip_edges()])
