extends GutTest
## GEN-08: every spine of a run walks. A seed's plan is made on a deriver with GEN-07's road pack
## (grid cells, every main-road shape, plain fallbacks), and only base camp, each spine's cells and
## its target's door cell are committed into a mine. A walker goes from the tile beyond the spine's
## gate, through the opening into each next cell in turn, to the middle of the target's door: so
## the spine alone joins base camp to its target, through its forced-open sockets. (Hop by hop:
## GEN-01's path query looks no further than about 500 tiles.) No old fall lies on a spine.
## (Collapse points join once HAZ-03 arms them: forced fallen, the walk must still hold, GEN-12's
## check.)

const Specs = preload("res://tests/unit/gen/template_specs.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _params(kind: int, jobs: Array[String]) -> Dictionary:
	return {"list_kind": kind, "jobs": PackedStringArray(jobs), "cans": RepairList.cans_for(kind as RepairList.Kind),
		"solo": false, "draw": PackedStringArray(), "staging": "", "hard_variant": "", "data_version": "",
		"tuning": RunPlan.tuning()}


## Base camp's edge tile in the middle of side `out`, on the main-road axis.
static func _edge_mid(out: Vector2i) -> Vector2i:
	if out.x > 0:
		return Vector2i(20, 10)
	if out.x < 0:
		return Vector2i(-1, 10)
	if out.y > 0:
		return Vector2i(10, 20)
	return Vector2i(10, -1)


## The middle tile of the opening on `cell`'s `side`, just inside it.
static func _opening_tile(cell: Vector2i, side: String, offset: int) -> Vector2i:
	var origin: Vector2i = cell * 20
	match side:
		"west":
			return origin + Vector2i(0, offset)
		"east":
			return origin + Vector2i(19, offset)
		"north":
			return origin + Vector2i(offset, 0)
	return origin + Vector2i(offset, 19)


## The side of `a` that `b` lies beyond.
static func _side(a: Vector2i, b: Vector2i) -> String:
	if b.x > a.x:
		return "east"
	if b.x < a.x:
		return "west"
	return "south" if b.y > a.y else "north"


const OPPOSITE: Dictionary = {"east": "west", "west": "east", "north": "south", "south": "north"}


func test_every_spine_joins_base_camp_to_its_target() -> void:
	var problems: Array[String] = []
	var pack: PackedByteArray = Specs.road_pack(problems)
	assert_eq(problems.size(), 0, str(problems.slice(0, 3)))
	var lists: Array = [[RepairList.Kind.SHORT, ["power", "fuel", "start"]],
		[RepairList.Kind.STANDARD, ["power", "fuel", "magneto", "brake_shoes", "start"]],
		[RepairList.Kind.FULL, ["power", "fuel", "drive_belt", "brake_shoes", "drum_gear", "rope_clamps", "start"]]]
	var walked: int = 0
	var cells_walked: int = 0
	var broken: Array[String] = []
	for i: int in 6:
		var run_seed: int = 7919 * (i + 3)
		for raw: Variant in lists:
			var list: Array = raw
			var kind: int = int(Variants.number(list[0]))
			var jobs: Array[String] = []
			jobs.assign(Variants.array(list[1]))
			var layouts: LbLayouts = LbLayouts.new()
			assert_true(layouts.load_pack(pack))
			MineLayouts.configure(layouts, run_seed)
			var plan: Dictionary = layouts.plan(_params(kind, jobs))
			assert_true(Variants.flag(plan["ok"]), str(plan["error"]))
			var sites: Array = Variants.array(plan["sites"])
			for sraw: Variant in Variants.array(plan["spines"]):
				var spine: Dictionary = sraw
				var site: Dictionary = sites[int(Variants.number(spine["site"]))]
				var mine: Mine = Mine.new()
				mine.native.commit(Basecamp.cell_data(run_seed))
				var cells: Array[Vector2i] = []
				cells.assign(Variants.array(spine["cells"]))
				var door: Vector2i = site["door"]
				for c: Vector2i in cells + ([door] as Array[Vector2i]):
					var road: Dictionary = layouts.road_of(c)
					if Variants.flag(road.get("old_fall", false)):
						broken.append("seed %d list %d: an old fall on spine cell %s" % [run_seed, kind, c])
					var data: LbCellData = MineLayouts.cell_data(layouts, run_seed, c)
					if data == null:
						broken.append("seed %d list %d: spine cell %s derives nothing" % [run_seed, kind, c])
						continue
					mine.native.commit(data)
				var gate: String = str(spine["gate"])
				var out: Vector2i = Basecamp.OUTWARD[Basecamp.SIDES.find(gate)]
				# The walker's stops: beyond the gate, the opening into each next cell, the door.
				var stops: Array[Vector2i] = [_edge_mid(out) + out]
				var path: Array[Vector2i] = cells + ([door] as Array[Vector2i])
				var shut: bool = false
				for k: int in range(1, path.size()):
					var side: String = _side(path[k - 1], path[k])
					var socket: Dictionary = layouts.socket(path[k - 1], side)
					if not Variants.flag(socket.get("open", false)):
						broken.append("seed %d list %d: spine edge %s-%s is shut" % [run_seed, kind, path[k - 1], path[k]])
						shut = true
						break
					var entry: String = str(OPPOSITE[side])
					stops.append(_opening_tile(path[k], entry, int(Variants.number(socket["offset"]))))
				if shut:
					continue
				var lost: String = ""
				for k: int in range(1, stops.size()):
					var answer: Mine.PathAnswer = mine.path_distance(stops[k - 1], stops[k], 200.0)
					if answer.distance < 0.0:
						lost = "from %s to %s" % [stops[k - 1], stops[k]]
						break
				if not lost.is_empty():
					broken.append("seed %d list %d: the walk to the %s is lost %s" % [run_seed, kind, str(site["kind"]), lost])
				else:
					walked += 1
					cells_walked += cells.size()
	assert_eq(broken, [] as Array[String])
	gut.p("spines walked: %d, through %d cells" % [walked, cells_walked])
	assert_gt(walked, 100)
