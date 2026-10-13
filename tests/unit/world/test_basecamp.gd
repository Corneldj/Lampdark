extends GutTest
## GEN-02's layout: rotations, the gates and forced sockets, brick faces, the arch overlay (with a
## branch inside 10 tiles), the inside set, the anchors, the deck and the shaft lining.

const B = preload("res://tests/scenario/world/basecamp_world.gd")
const TABLE: Dictionary = {"lamp_hook": 1, "switchboard_seat": 1, "map_table": 1, "medbay_table": 2, "medbay_cupboard": 1,
	"manual_lectern": 1, "bench": 1, "relighter": 1, "battery_rack": 1, "bess_stall": 1, "gate_lever": 6, "cage_deck": 1,
	"signal_cord": 1, "cage_guides": 2, "engine_prime": 1, "engine_crank": 1, "engine_throttle": 1, "tank_filler": 1,
	"magneto_mount": 1, "belt_mount": 1, "brake_mount": 1, "drum_gear_mount": 2, "rope_clamp_points": 1, "emergency_lamp": 4}


func before_all() -> void:
	assert_true(Tuning.load_server())


func _rows(file: Dictionary) -> PackedStringArray:
	return PackedStringArray(Variants.array(file["tiles"]))


func test_rotations_round_trip() -> void:
	var c: Dictionary = Basecamp.canonical()
	var want: String = CellFile.serialize(CellFile.from_dict(c, "canonical"))
	for k: int in 4:
		var back: Dictionary = Basecamp.rotate(Basecamp.rotate(c, k), 4 - k)
		assert_eq(CellFile.serialize(CellFile.from_dict(back, "back")), want, "rotation %d and back: identical tiles, zones, anchors, gates" % k)
	assert_ne(JSON.stringify(Basecamp.rotate(c, 1)["tiles"]), JSON.stringify(c["tiles"]))


func test_gates_and_sockets() -> void:
	for side: int in 4:
		var gates: Array[Dictionary] = Basecamp.gate_specs(0, side)
		assert_eq(gates.size(), 3)
		var sides: Dictionary = {}
		for g: Dictionary in gates:
			sides[g["side"]] = true
			var tiles: Array = g["tiles"]
			assert_eq(tiles.size(), roundi(Tuning.f(&"basecamp.gate_width_tiles")), "3 wide")
			var centre: Vector2 = Vector2.ZERO
			for t: Vector2i in tiles:
				centre += Vector2(t) + Vector2(0.5, 0.5)
			centre /= tiles.size()
			var outward: Vector2i = g["outward"]
			var across: float = centre.y if outward.x != 0 else centre.x
			assert_lte(absf(across - 10.0), 0.5, "centred on the main-road arm through the shaft")
			var mid: Vector2i = tiles[1]
			var road: Vector2i = mid + outward
			assert_true(".=~".contains(_rows(Basecamp.cell_dict(0, side))[road.y][road.x]), "it opens onto a road")
			assert_true(Variants.dict(g["levers"]).has("inside") and Variants.dict(g["levers"]).has("outside"), "a lever either side")
		assert_false(sides.has(Basecamp.SIDES[side]), "no gate on the blind side")
		assert_eq(sides.size(), 3, "three sides")
		var sockets: Dictionary = Basecamp.forced_sockets(0, side)
		for s: int in 4:
			var socket: String = sockets[Basecamp.SIDES[s]]
			assert_eq(socket, "shut" if s == side else "open")
		# The blind edge is shut rock.
		var rows: PackedStringArray = _rows(Basecamp.cell_dict(0, side))
		for i: int in 20:
			var t: Vector2i = [Vector2i(i, 0), Vector2i(19, i), Vector2i(i, 19), Vector2i(0, i)][side]
			assert_false(".=~s".contains(rows[t.y][t.x]), "the blind edge is solid at %s" % t)


func test_brick_faces_and_arches() -> void:
	for side: int in 4:
		var rows: PackedStringArray = _rows(Basecamp.cell_dict(0, side))
		var inside: Dictionary = Basecamp.inside_tiles(0, side)
		for raw: Variant in inside.keys():
			var t: Vector2i = raw
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
				var n: Vector2i = t + d
				var ch: String = rows[n.y][n.x]
				assert_true(ch == "B" or ch == "s" or ch == "S" or inside.has(n), "base camp's faces are brick (or a gate): %s" % n)
		assert_eq(Basecamp.check_gate_arches(0, Vector2i.ZERO, rows, side), [] as Array[String], "base camp's own arches")
		for g: Dictionary in Basecamp.gate_specs(0, side):
			var road: Array = B.road_cell(g)
			var cell: Vector2i = road[0]
			var raw_rows: PackedStringArray = road[1]
			assert_false(Basecamp.check_gate_arches(0, cell, raw_rows, side).is_empty(), "raw rock beside the arches fails the check")
			var arched: PackedStringArray = Basecamp.apply_gate_arches(0, cell, raw_rows, side)
			assert_eq(Basecamp.check_gate_arches(0, cell, arched, side), [] as Array[String], "the overlay fixes it")
			var arch: Dictionary = Basecamp.arch_tiles(0, cell, arched, side)
			var deepest: int = 0
			var branch: int = 0
			for raw: Variant in arch.keys():
				deepest = maxi(deepest, int(Variants.number(arch[raw])))
			assert_eq(deepest, roundi(Tuning.f(&"basecamp.arch_length_tiles")), "out to exactly 10 tiles by path")
			for y: int in 20:
				for x: int in 20:
					var w: Vector2i = cell * 20 + Vector2i(x, y)
					if arched[y][x] == "." and arch.has(w):
						var tiles: Array = g["tiles"]
						var outward: Vector2i = g["outward"]
						var first: Vector2i = tiles[0]
						var offset: Vector2i = w - first
						if (outward.x != 0 and (offset.y < 0 or offset.y > 2)) or (outward.y != 0 and (offset.x < 0 or offset.x > 2)):
							branch += 1
			assert_gt(branch, 0, "a branch inside the 10 tiles is arched too")
			var beyond: int = 0
			for y: int in 20:
				for x: int in 20:
					if arched[y][x] == "#":
						beyond += 1
			assert_gt(beyond, 100, "past the arches, rock")


func test_inside_set() -> void:
	for side: int in 4:
		var rows: PackedStringArray = _rows(Basecamp.cell_dict(0, side))
		var inside: Dictionary = Basecamp.inside_tiles(0, side)
		assert_eq(inside.size(), 16 * 12, "the complex's floor, about 16 x 12")
		var deck: Rect2i = Basecamp.deck_rect(0, side)
		for y: int in range(deck.position.y, deck.end.y):
			for x: int in range(deck.position.x, deck.end.x):
				assert_true(inside.has(Vector2i(x, y)), "the deck is inside")
		for g: Dictionary in Basecamp.gate_specs(0, side):
			var outward: Vector2i = g["outward"]
			for t: Vector2i in Variants.array(g["tiles"]):
				assert_false(Basecamp.is_inside_base_camp(0, t + outward, side), "an arch tile is road, not base camp")
		for raw: Variant in inside.keys():
			var t: Vector2i = raw
			assert_true(".=~".contains(rows[t.y][t.x]))


func test_anchors() -> void:
	for side: int in 4:
		var rows: PackedStringArray = _rows(Basecamp.cell_dict(0, side))
		for name: String in TABLE.keys():
			var found: Array[Dictionary] = Basecamp.fixture(0, name, side)
			assert_eq(found.size(), int(Variants.number(TABLE[name])), "%s count" % name)
			for a: Dictionary in found:
				var p: Vector2i = a["position"]
				var reachable: bool = false
				for dy: int in range(-1, 2):
					for dx: int in range(-1, 2):
						var t: Vector2i = p + Vector2i(dx, dy)
						if t.x >= 0 and t.x < 20 and t.y >= 0 and t.y < 20 and ".=~".contains(rows[t.y][t.x]):
							reachable = true
				assert_true(reachable, "%s at %s has floor in touch range" % [name, p])
				assert_true(["N", "E", "S", "W"].has(a["facing"]), "a facing")
	var guides: Array[Dictionary] = Basecamp.fixture(0, "drum_gear_mount", 0)
	var p0: Vector2i = guides[0]["position"]
	var p1: Vector2i = guides[1]["position"]
	assert_ne(p0, p1, "two carrier points, one miner each")


func test_deck_and_shaft() -> void:
	for side: int in 4:
		var deck: Rect2i = Basecamp.deck_rect(0, side)
		assert_eq(deck.size.x * deck.size.y, roundi(Tuning.f(&"lift.cage_deck_width_tiles") * Tuning.f(&"lift.cage_deck_length_tiles")), "4 x 5")
		var far: int = 0
		var samples: int = 0
		for iy: int in deck.size.y * 20:
			for ix: int in deck.size.x * 20:
				var p: Vector2 = Vector2(deck.position) + Vector2(ix + 0.5, iy + 0.5) / 20.0
				samples += 1
				if Basecamp.deck_side_distance(0, p, side) > Tuning.f(&"tapper.reach_tiles"):
					far += 1
		assert_almost_eq(float(far) / samples * deck.size.x * deck.size.y, 2.0, 0.05, "exactly a 1 x 2 middle beyond 1.5 tiles of every side")
	assert_eq(Basecamp.shaft_lining_at(0.0), WorldIds.TileMaterial.BRICK)
	assert_eq(Basecamp.shaft_lining_at(150.0), WorldIds.TileMaterial.BRICK)
	assert_eq(Basecamp.shaft_lining_at(151.0), WorldIds.TileMaterial.ROCK)
	assert_eq(Basecamp.shaft_lining_at(300.0), WorldIds.TileMaterial.ROCK)
	assert_eq(Tuning.f(&"lift.shaft_depth_m"), 300.0)


func test_loads_through_gen01() -> void:
	for side: int in 4:
		var data: LbCellData = Basecamp.cell_data(0, side)
		assert_not_null(data, "rotation %d loads as a cell" % side)
		var mine: Mine = Mine.new()
		mine.native.commit(data)
		var graph: RoadGraphService = RoadGraphService.new(mine, 1)
		assert_eq(graph.failed_cells, [] as Array[Vector2i], "its zones and gate portals stitch")
