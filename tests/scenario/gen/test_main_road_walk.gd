extends GutTest
## GEN-07: the arms out of base camp, derived from a pack with every main-road shape and committed
## into a mine. Each gate arm runs from its gate to the first crossing: its runs between bends,
## base camp and the crossing are 25-40 tiles; its rails run unbroken across every edge (stopping
## only at an old fall); and a walk along it reaches the crossing unless an old fall chokes it, when
## the way round starts at the fall's exits. The blind arm's first cell faces base camp with a
## blind heading. (A miner walking it in the running simulation waits for GEN-11's live generation.)

const Specs = preload("res://tests/unit/gen/template_specs.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_the_arms_from_the_gates_to_the_first_crossing() -> void:
	var problems: Array[String] = []
	var pack: PackedByteArray = Specs.road_pack(problems)
	assert_eq(problems.size(), 0, str(problems.slice(0, 3)))
	var spacing: int = Tuning.i(&"mine.main_road_spacing_cells")
	var run_min: int = roundi(Tuning.f(&"mine.main_road_run_min_tiles"))
	var run_max: int = roundi(Tuning.f(&"mine.main_road_run_max_tiles"))
	var arms: int = 0
	var falls: int = 0
	var broken: Array[String] = []
	for i: int in 12:
		var run_seed: int = 31 * (i + 7)
		var layouts: LbLayouts = LbLayouts.new()
		assert_true(layouts.load_pack(pack))
		MineLayouts.configure(layouts, run_seed)
		var mine: Mine = Mine.new()
		mine.native.commit(Basecamp.cell_data(run_seed))
		var blind: int = Basecamp.blind_side(run_seed)
		for s: int in 4:
			var out: Vector2i = Basecamp.OUTWARD[s]
			var cells: Array[Vector2i] = []
			for k: int in range(1, spacing + 1):
				var c: Vector2i = out * k
				var data: LbCellData = MineLayouts.cell_data(layouts, run_seed, c)
				assert_not_null(data, "arm cell %s derives" % c)
				if data == null:
					continue
				mine.native.commit(data)
				cells.append(c)
			if s == blind:
				# The blind arm's first cell: rock where base camp's blind side meets it.
				assert_false(mine.native.is_walkable(_edge_mid(out), true), "seed %d: the blind arm starts with a blind heading" % run_seed)
				continue
			arms += 1
			# Runs: base camp's centre, each bend, the crossing's centre (world positions along the
			# arm), 25-40 tiles apart.
			var marks: Array[int] = [10]
			var fall: bool = false
			for k: int in range(1, spacing + 1):
				var c: Vector2i = out * k
				var along: int = c.x if out.x != 0 else c.y
				var road: Dictionary = layouts.road_of(c)
				if Variants.flag(road.get("old_fall", false)):
					fall = true
				var shape: String = str(road.get("shape", ""))
				if shape.begins_with("bend_"):
					marks.append(along * 20 + int(shape.substr(5)))
				elif shape == "crossing":
					marks.append(along * 20 + 10)
			marks.sort()
			for m: int in range(1, marks.size()):
				var gap: int = marks[m] - marks[m - 1]
				if gap < run_min or gap > run_max:
					broken.append("seed %d side %d: a run of %d" % [run_seed, s, gap])
			# Rails across every edge of the arm, and a walk to the crossing unless a fall chokes it.
			for k: int in range(1, spacing):
				var a: Vector2i = out * k
				var b: Vector2i = out * (k + 1)
				for tile: Vector2i in _edge_pair(a, b):
					if mine.native.material_at(tile) != WorldIds.TileMaterial.FLOOR or (mine.native.state_at(tile) & CellFile.STATE_RAIL) == 0:
						broken.append("seed %d side %d: no rail at %s" % [run_seed, s, tile])
			var start: Vector2i = _edge_mid(out) + out
			var goal: Vector2i = out * spacing * 20 + Vector2i(10, 10)
			var answer: Mine.PathAnswer = mine.path_distance(start, goal, 400.0)
			if fall:
				falls += 1
			elif answer.distance < 0.0:
				broken.append("seed %d side %d: the arm does not reach its crossing" % [run_seed, s])
	assert_eq(broken, [] as Array[String])
	assert_eq(arms, 36)
	gut.p("arms walked: %d, with an old fall: %d" % [arms, falls])


## Base camp's edge tile in the middle of side `out`, on the main-road axis.
static func _edge_mid(out: Vector2i) -> Vector2i:
	if out.x > 0:
		return Vector2i(20, 10)
	if out.x < 0:
		return Vector2i(-1, 10)
	if out.y > 0:
		return Vector2i(10, 20)
	return Vector2i(10, -1)


## The two tiles facing each other on the road's centre line across the edge between a and b.
static func _edge_pair(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var d: Vector2i = b - a
	if d.x != 0:
		var x: int = maxi(a.x, b.x) * 20
		return [Vector2i(x - 1, a.y * 20 + 10), Vector2i(x, a.y * 20 + 10)]
	var y: int = maxi(a.y, b.y) * 20
	return [Vector2i(a.x * 20 + 10, y - 1), Vector2i(a.x * 20 + 10, y)]
