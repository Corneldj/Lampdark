class_name M1GreyboxCheck
extends RefCounted
## GEN-03: proves the grey box still holds every feature the kill test's five criteria need (GDD §16.5;
## Gameplay §A.11, §7.2, §7.3, §6.1, §6.2, §4.4, §12.7, §10.6). It reads only GEN-01's queries
## (walkability, materials, the strike field, rock thickness, paths), the cells' anchors and zones, the
## placements and SND-01's rock line, so GEN-12 can reuse the checks on generated cells. Each failure
## names its requirement first ("widths: ...").

const RICH: int = 4                 # rock this thick is rich (Tapper.start_tile)
const REACH_MILLI: int = 1500       # the Tapper's reach, 1.5 tiles
const HOOK_SPACING: int = 6         # about one hook per 6 tiles of road
const SIGHT_MIN: int = 25
const SIGHT_MAX: int = 40
const DEPTH_MIN: float = 40.0
const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const FORBIDDEN: Array[String] = ["gas_area", "gas_dead_end", "trap_site", "collapse", "poi_slot"]
const CHARS: Dictionary = {0: ".", 1: "#", 2: "c", 3: "B", 4: "T", 5: "S", 6: "D"}


class Ctx:
	extends RefCounted
	var mine: Mine
	var seed_value: int = 0
	var side: int = 0
	var cells: Array[Vector2i] = []
	## world tile -> true, walkable with doors open, in the maze cells
	var floor: Dictionary = {}
	## [rect (Rect2i, world), tags (PackedStringArray), cell]
	var chambers: Array[Array] = []
	## world tile -> true: tiles inside a chamber rectangle
	var in_chamber: Dictionary = {}
	var roads: Dictionary = {}
	var arch: Dictionary = {}
	## [type, world tile, size, tags, kind, cell]
	var anchors: Array[Array] = []

	func is_floor(t: Vector2i) -> bool:
		return floor.has(t)


## Every requirement's failures; empty when the maze holds them all. `placements` defaults to the
## map's file; `graph` (SND-01's) checks the voice pairs' rock lines and each cell's zone block.
static func check(mine: Mine, map_name: String = "m1_greybox", placements: Dictionary = {}, graph: LbRoadGraph = null) -> Array[String]:
	var m: Dictionary = FixedMapLoader.manifest(map_name)
	if placements.is_empty():
		placements = FixedMapLoader.placements(map_name)
	var c: Ctx = _context(mine, m)
	var errors: Array[String] = []
	errors.append_array(_gate_roads(c))
	errors.append_array(_widths(c))
	errors.append_array(_connectivity(c))
	errors.append_array(_sight_line(c))
	errors.append_array(_depth(c))
	errors.append_array(_coat_heaps(c, placements))
	errors.append_array(_rock_faces(c))
	errors.append_array(_centre_lines(c))
	errors.append_array(_rich_rock(c))
	errors.append_array(_voice_pairs(c, graph))
	errors.append_array(_air_door(c))
	errors.append_array(_hooks_rubble(c))
	errors.append_array(_landmarks(c))
	errors.append_array(_ring(c))
	errors.append_array(_nothing_else(c))
	if graph != null:
		for cell: Vector2i in c.cells:
			for e: String in graph.validate(cell):
				errors.append("road_graph: cell %s: %s" % [cell, e])
	return errors


## Every chamber's centre and every dead end (QA-01's walk; FND-09's bots go to each and back).
static func walk_targets(mine: Mine, map_name: String = "m1_greybox") -> Array[Vector2i]:
	var c: Ctx = _context(mine, FixedMapLoader.manifest(map_name))
	var out: Array[Vector2i] = []
	for ch: Array in c.chambers:
		var r: Rect2i = ch[0]
		out.append(r.position + r.size / 2)
	out.append_array(_dead_ends(c))
	out.sort()
	return out


static func _context(mine: Mine, m: Dictionary) -> Ctx:
	var c: Ctx = Ctx.new()
	c.mine = mine
	c.seed_value = FixedMapLoader.run_seed(m)
	c.side = FixedMapLoader.blind_side(m)
	for raw: Variant in Variants.array(m.get("cells", [])):
		var a: Array = raw
		c.cells.append(Vector2i(int(Variants.number(a[0])), int(Variants.number(a[1]))))
	for cell: Vector2i in c.cells:
		for y: int in WorldIds.CELL_TILES:
			for x: int in WorldIds.CELL_TILES:
				var t: Vector2i = WorldCoords.tile_of(cell, Vector2i(x, y))
				if mine.native.is_walkable(t, true):
					c.floor[t] = true
		for a: Dictionary in mine.native.anchors(cell):
			var at: Vector2i = WorldCoords.tile_of(cell, Vector2i(int(Variants.number(a["x"])), int(Variants.number(a["y"]))))
			var size: Vector2i = Vector2i(int(Variants.number(a["w"])), int(Variants.number(a["h"])))
			var tags: PackedStringArray = a.get("tags", PackedStringArray())
			c.anchors.append([str(a["type"]), at, size, tags, str(a.get("kind", "")), cell])
			if str(a["type"]) == "chamber":
				var rect: Rect2i = Rect2i(at, size)
				c.chambers.append([rect, tags, cell])
				for y: int in range(rect.position.y, rect.end.y):
					for x: int in range(rect.position.x, rect.end.x):
						c.in_chamber[Vector2i(x, y)] = true
		c.arch.merge(Basecamp.arch_tiles(c.seed_value, cell, rows_of(mine, cell), c.side))
	for raw: Variant in c.floor.keys():
		var t: Vector2i = raw
		if not c.in_chamber.has(t) and not _is_door(mine, t):
			c.roads[t] = true
	return c


## A cell as GEN-01's characters, for GEN-02's arch rule.
static func rows_of(mine: Mine, cell: Vector2i) -> PackedStringArray:
	var rows: PackedStringArray = PackedStringArray()
	for y: int in WorldIds.CELL_TILES:
		var row: String = ""
		for x: int in WorldIds.CELL_TILES:
			var t: Vector2i = WorldCoords.tile_of(cell, Vector2i(x, y))
			var material: int = mine.native.material_at(t)
			var state: int = mine.native.state_at(t)
			var ch: String = str(CHARS.get(material, "#"))
			if material == 0 and (state & 2) != 0:
				ch = "="
			elif material == 0 and (state & 4) != 0:
				ch = "~"
			elif (material == 5 or material == 6) and (state & 1) != 0:
				ch = ch.to_lower()
			row += ch
		rows.append(row)
	return rows


static func _is_door(mine: Mine, t: Vector2i) -> bool:
	var material: int = mine.native.material_at(t)
	return material == WorldIds.TileMaterial.WOODEN_DOOR or material == WorldIds.TileMaterial.STEEL


static func _in_maze(c: Ctx, t: Vector2i) -> bool:
	return c.cells.has(WorldCoords.cell_of(t))


static func _gate_roads(c: Ctx) -> Array[String]:
	var errors: Array[String] = []
	for g: Dictionary in Basecamp.gate_specs(c.seed_value, c.side):
		var outward: Vector2i = g["outward"]
		var tiles: Array = g["tiles"]
		var lateral: Vector2i = Vector2i(absi(outward.y), absi(outward.x))
		var mid: Vector2i = tiles[1]
		# Out of the gate to the maze cell's edge, then 10 tiles of 3-wide railed road.
		var t: Vector2i = mid + outward
		while not _in_maze(c, t) and absi(t.x) < 200 and absi(t.y) < 200:
			t += outward
		for k: int in 10:
			var row: Vector2i = t + outward * k
			for s: int in [-1, 0, 1]:
				if not c.is_floor(row + lateral * s):
					errors.append("gate_roads: the %s gate's road is not 3 wide at %s" % [g["side"], row + lateral * s])
			if (c.mine.native.state_at(row) & 2) == 0:
				errors.append("gate_roads: the %s gate's road has no rail at %s" % [g["side"], row])
		for cell: Vector2i in c.cells:
			for e: String in Basecamp.check_gate_arches(c.seed_value, cell, rows_of(c.mine, cell), c.side):
				errors.append("gate_roads: %s" % e)
	return errors


## On an arch, or at its mouth (a tile the arch's brick still flanks).
static func _on_arch(c: Ctx, t: Vector2i) -> bool:
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if c.arch.has(t + Vector2i(dx, dy)):
				return true
	return false


## Width of road at a tile: the shorter of its horizontal and vertical road runs.
static func _width(c: Ctx, t: Vector2i) -> int:
	var runs: Array[int] = []
	for axis: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
		var n: int = 1
		var p: Vector2i = t + axis
		while c.roads.has(p):
			n += 1
			p += axis
		p = t - axis
		while c.roads.has(p):
			n += 1
			p -= axis
		runs.append(n)
	return mini(runs[0], runs[1])


static func _widths(c: Ctx) -> Array[String]:
	var errors: Array[String] = []
	var seen: Dictionary = {}
	for raw: Variant in c.roads.keys():
		var t: Vector2i = raw
		seen[_width(c, t)] = true
	for w: int in [1, 2, 3]:
		if not seen.has(w):
			errors.append("widths: no road stretch %d wide" % w)
	for ch: Array in c.chambers:
		var r: Rect2i = ch[0]
		if r.size.x < 5 or r.size.x > 8 or r.size.y < 5 or r.size.y > 8:
			errors.append("widths: chamber at %s is %dx%d; chambers are 5-8 across, never 4" % [r.position, r.size.x, r.size.y])
	return errors


static func _connectivity(c: Ctx) -> Array[String]:
	var errors: Array[String] = []
	var camp: Vector2i = _camp_floor(c)
	var all_floor: int = c.floor.size()
	for y: int in WorldIds.CELL_TILES:
		for x: int in WorldIds.CELL_TILES:
			if c.mine.native.is_walkable(Vector2i(x, y), true):
				all_floor += 1
	var reached: int = c.mine.native.flood_count(camp, 150000, true)  # 150 tiles: the whole map (and within walk()'s window)
	if reached != all_floor:
		errors.append("connectivity: %d of %d floor tiles connect to base camp with the door open" % [reached, all_floor])
	# A loop: out of one gate and back by another without crossing base camp.
	var outs: Array[Vector2i] = []
	for g: Dictionary in Basecamp.gate_specs(c.seed_value, c.side):
		var outward: Vector2i = g["outward"]
		var gate_tiles: Array = g["tiles"]
		var mid_tile: Vector2i = gate_tiles[1]
		var t: Vector2i = mid_tile + outward
		while not _in_maze(c, t) and absi(t.x) < 200:
			t += outward
		outs.append(t)
	var looped: bool = false
	for i: int in outs.size():
		var region: Dictionary = _flood(c, outs[i], func(t: Vector2i) -> bool: return c.is_floor(t))
		for j: int in outs.size():
			if j != i and region.has(outs[j]):
				looped = true
	if not looped:
		errors.append("connectivity: no loop out of one gate and back by another")
	if _dead_ends(c).size() < 2:
		errors.append("connectivity: %d dead ends; at least two" % _dead_ends(c).size())
	return errors


static func _dead_ends(c: Ctx) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for raw: Variant in c.roads.keys():
		var t: Vector2i = raw
		var n: int = 0
		for d: Vector2i in DIRS4:
			if c.mine.native.is_walkable(t + d, true):
				n += 1
		if n == 1:
			out.append(t)
	return out


static func _flood(_c: Ctx, from: Vector2i, ok: Callable) -> Dictionary:
	var seen: Dictionary = {from: true}
	var stack: Array[Vector2i] = [from]
	while not stack.is_empty():
		var t: Vector2i = stack.pop_back()
		for d: Vector2i in DIRS4:
			var n: Vector2i = t + d
			if not seen.has(n) and Variants.flag(ok.call(n)):
				seen[n] = true
				stack.append(n)
	return seen


## The longest straight floor runs, rows and columns: [length, start, axis].
static func _runs(c: Ctx) -> Array[Array]:
	var out: Array[Array] = []
	for raw: Variant in c.floor.keys():
		var t: Vector2i = raw
		for axis: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			if c.is_floor(t - axis):
				continue
			var n: int = 0
			while c.is_floor(t + axis * n):
				n += 1
			out.append([n, t, axis])
	return out


static func _sight_line(c: Ctx) -> Array[String]:
	for r: Array in _runs(c):
		var n: int = r[0]
		if n >= SIGHT_MIN and n <= SIGHT_MAX:
			return [] as Array[String]
	return ["sight_line: no straight run of %d-%d tiles" % [SIGHT_MIN, SIGHT_MAX]] as Array[String]


static func _depth(c: Ctx) -> Array[String]:
	var targets: Array[Vector2i] = _dead_ends(c)
	for ch: Array in c.chambers:
		var r: Rect2i = ch[0]
		targets.append(r.position + r.size / 2)
	var gates: Array[Vector2i] = []
	for g: Dictionary in Basecamp.gate_specs(c.seed_value, c.side):
		var gate_tiles: Array = g["tiles"]
		var mid_tile: Vector2i = gate_tiles[1]
		var outward: Vector2i = g["outward"]
		gates.append(mid_tile + outward)
	var deepest: float = 0.0
	for t: Vector2i in targets:
		var nearest: float = INF
		for g: Vector2i in gates:
			var a: Mine.PathAnswer = c.mine.path_distance(g, t, 160.0, true)
			if a.distance >= 0.0:
				nearest = minf(nearest, a.distance)
		if nearest != INF:
			deepest = maxf(deepest, nearest)
	if deepest < DEPTH_MIN:
		return ["depth: the deepest chamber or dead end is %.1f tiles from a gate; at least %.0f" % [deepest, DEPTH_MIN]] as Array[String]
	return [] as Array[String]


static func _coat_heaps(c: Ctx, placements: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var heaps: Array[Vector2i] = []
	for raw: Variant in Variants.array(placements.get("coat_heaps", [])):
		var a: Array = raw
		heaps.append(Vector2i(int(Variants.number(a[0])), int(Variants.number(a[1]))))
	var ribs: Dictionary = {}
	for a: Array in c.anchors:
		var tags: PackedStringArray = a[3]
		if str(a[0]) == "timber_hook" and tags.has("rib"):
			ribs[a[1]] = true
	var moth: Vector2i = Vector2i(-99999, -99999)
	for raw: Variant in Variants.array(placements.get("creatures", [])):
		var d: Dictionary = raw
		if str(d.get("kind", "")) == "MOTH":
			var t: Array = d["tile"]
			moth = Vector2i(int(Variants.number(t[0])), int(Variants.number(t[1])))
	var coat: int = 0
	var roost: bool = false
	var hoard: bool = false
	var seen_far: bool = false
	for ch: Array in c.chambers:
		var r: Rect2i = ch[0]
		var tags: PackedStringArray = ch[1]
		if not tags.has("coat_heaps"):
			continue
		coat += 1
		var mine_heaps: Array[Vector2i] = []
		for h: Vector2i in heaps:
			if r.has_point(h):
				mine_heaps.append(h)
				if not ribs.has(h):
					errors.append("coat_heaps: the heap at %s hangs on no rib hook" % h)
		if mine_heaps.size() < 4 or mine_heaps.size() > 6:
			errors.append("coat_heaps: the chamber at %s has %d heaps; 4-6" % [r.position, mine_heaps.size()])
		if tags.has("roost"):
			roost = roost or r.has_point(moth)
		hoard = hoard or tags.has("hoard")
		if not _far_rib(c, r, mine_heaps):
			errors.append("coat_heaps: no way along the far rib 2+ tiles from every heap in the chamber at %s" % r.position)
		seen_far = seen_far or _seen_along_road(c, r, 20)
	if coat < 2:
		errors.append("coat_heaps: %d coat-heap chambers; at least two" % coat)
	if not roost:
		errors.append("coat_heaps: the Moth does not start in the roost")
	if not hoard:
		errors.append("coat_heaps: no chamber is tagged as the hoard")
	if not seen_far:
		errors.append("coat_heaps: no coat chamber is seen along a straight road of 20+ tiles")
	return errors


## From the chamber's ways in, the tiles 2+ from every heap reach a whole side of the chamber.
static func _far_rib(c: Ctx, r: Rect2i, heaps: Array[Vector2i]) -> bool:
	var clear: Callable = func(t: Vector2i) -> bool:
		if not (r.has_point(t) and c.is_floor(t)):
			return false
		for h: Vector2i in heaps:
			if maxi(absi(h.x - t.x), absi(h.y - t.y)) < 2:
				return false
		return true
	var reach: Dictionary = {}
	for y: int in range(r.position.y - 1, r.end.y + 1):
		for x: int in range(r.position.x - 1, r.end.x + 1):
			var t: Vector2i = Vector2i(x, y)
			if r.has_point(t) or not c.is_floor(t):
				continue
			for d: Vector2i in DIRS4:
				if Variants.flag(clear.call(t + d)) and not reach.has(t + d):
					reach.merge(_flood(c, t + d, clear))
	var sides: Array[Array] = [[r.position, Vector2i(1, 0), r.size.x], [Vector2i(r.position.x, r.end.y - 1), Vector2i(1, 0), r.size.x],
		[r.position, Vector2i(0, 1), r.size.y], [Vector2i(r.end.x - 1, r.position.y), Vector2i(0, 1), r.size.y]]
	for s: Array in sides:
		var all: bool = true
		for k: int in int(Variants.number(s[2])):
			var origin: Vector2i = s[0]
			var step: Vector2i = s[1]
			if not reach.has(origin + step * k):
				all = false
		if all:
			return true
	return false


## A straight road of `n`+ tiles runs into the chamber.
static func _seen_along_road(c: Ctx, r: Rect2i, n: int) -> bool:
	for run: Array in _runs(c):
		var start: Vector2i = run[1]
		var axis: Vector2i = run[2]
		var outside: int = 0
		var enters: bool = false
		for k: int in int(Variants.number(run[0])):
			var t: Vector2i = start + axis * k
			if r.has_point(t):
				enters = true
			elif c.roads.has(t) or not c.in_chamber.has(t):
				outside += 1
		if enters and outside >= n:
			return true
	return false


## A floor tile inside base camp (the shaft at its centre is not floor).
static func _camp_floor(c: Ctx) -> Vector2i:
	var inside: Dictionary = Basecamp.inside_tiles(c.seed_value, c.side)
	var keys: Array = inside.keys()
	keys.sort()
	for raw: Variant in keys:
		var t: Vector2i = raw
		if c.mine.native.is_walkable(t, true):
			return t
	return Vector2i(10, 10)


static func _rock_faces(c: Ctx) -> Array[String]:
	var errors: Array[String] = []
	for raw: Variant in c.roads.keys():
		var t: Vector2i = raw
		if _on_arch(c, t):
			continue
		var s: int = c.mine.native.strike_milli(t)
		if s < 0 or s > REACH_MILLI:
			errors.append("rock_faces: road tile %s is %s from a coal or stone face; within 1.5" % [t, "beyond 4" if s < 0 else str(s / 1000.0)])
	return errors


static func _centre_lines(c: Ctx) -> Array[String]:
	var five: bool = false
	var wide: bool = false
	for ch: Array in c.chambers:
		var r: Rect2i = ch[0]
		if r.size == Vector2i(5, 5):
			var out_of_reach: int = 0
			for y: int in range(r.position.y, r.end.y):
				for x: int in range(r.position.x, r.end.x):
					var s: int = c.mine.native.strike_milli(Vector2i(x, y))
					if s < 0 or s > REACH_MILLI:
						out_of_reach += 1
			five = five or out_of_reach == 1
		wide = wide or maxi(r.size.x, r.size.y) >= 7
	var errors: Array[String] = []
	if not five:
		errors.append("centre_lines: no 5x5 chamber with exactly one tile out of the Tapper's reach")
	if not wide:
		errors.append("centre_lines: no chamber 7-8 across")
	return errors


static func _rich_rock(c: Ctx) -> Array[String]:
	var rich: Dictionary = {}
	for cell: Vector2i in c.cells:
		for y: int in WorldIds.CELL_TILES:
			for x: int in WorldIds.CELL_TILES:
				var t: Vector2i = WorldCoords.tile_of(cell, Vector2i(x, y))
				if c.mine.native.thickness(t) >= RICH:
					rich[t] = true
	var masses: int = 0
	var counted: Dictionary = {}
	for raw: Variant in rich.keys():
		if counted.has(raw):
			continue
		var seed_tile: Vector2i = raw
		var mass: Dictionary = _flood(c, seed_tile, func(t: Vector2i) -> bool: return rich.has(t))
		counted.merge(mass)
		var beside: bool = false
		for m: Variant in mass.keys():
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
				var mt: Vector2i = m
				if c.roads.has(mt + d):
					beside = true
		if beside:
			masses += 1
	if masses < 2:
		return ["rich_rock: %d masses 4+ tiles thick beside a road; at least two" % masses] as Array[String]
	return [] as Array[String]


static func _voice_pairs(c: Ctx, graph: LbRoadGraph) -> Array[String]:
	var errors: Array[String] = []
	var found: Dictionary = {}
	for a: Array in c.anchors:
		var kind: String = str(a[4])
		if kind != "m1.voice_thin" and kind != "m1.voice_thick":
			continue
		var from: Vector2i = a[1]
		var to: Vector2i = from
		var tags: PackedStringArray = a[3]
		var anchor_cell: Vector2i = a[5]
		for tag: String in tags:
			if tag.begins_with("to:"):
				var parts: PackedStringArray = tag.substr(3).split(",")
				to = WorldCoords.tile_of(anchor_cell, Vector2i(parts[0].to_int(), parts[1].to_int()))
		if not c.roads.has(from) or not c.roads.has(to):
			errors.append("voice_pairs: %s's ends %s and %s are not both road" % [kind, from, to])
			continue
		var straight: float = Vector2(from).distance_to(Vector2(to))
		var road: Mine.PathAnswer = c.mine.path_distance(from, to, 160.0, true)
		if road.distance >= 0.0 and road.distance < straight * 2.0:
			errors.append("voice_pairs: %s's ends are the same road (%.1f tiles apart by road)" % [kind, road.distance])
			continue
		if graph != null:
			var line: Dictionary = graph.rock_line(from, to)
			var solid: int = int(Variants.number(line.get("solid_tiles", 0)))
			var clean: bool = not Variants.flag(line.get("brick", false)) and not Variants.flag(line.get("door", false))
			if kind == "m1.voice_thin" and not (clean and solid >= 1 and solid <= 2):
				errors.append("voice_pairs: the thin pair has %d tiles of rock (brick %s); 2 or fewer, never brick" % [solid, line.get("brick")])
				continue
			if kind == "m1.voice_thick" and solid < 3:
				errors.append("voice_pairs: the thick pair has %d tiles of rock; 3 or more" % solid)
				continue
		found[kind] = true
	for kind: String in ["m1.voice_thin", "m1.voice_thick"]:
		if not found.has(kind):
			errors.append("voice_pairs: no %s pair" % kind.trim_prefix("m1.voice_"))
	return errors


static func _air_door(c: Ctx) -> Array[String]:
	var errors: Array[String] = []
	var doors: int = 0
	for cell: Vector2i in c.cells:
		for b: Dictionary in c.mine.native.barriers(cell):
			if int(Variants.number(b.get("material", 0))) != WorldIds.TileMaterial.WOODEN_DOOR:
				continue
			doors += 1
			var tiles: Array = b["tiles"]
			var door: Vector2i = tiles[0]
			var coat: Rect2i = Rect2i()
			var road: bool = false
			for d: Vector2i in DIRS4:
				var n: Vector2i = door + d
				for ch: Array in c.chambers:
					var r: Rect2i = ch[0]
					var ch_tags: PackedStringArray = ch[1]
					if r.has_point(n) and ch_tags.has("coat_heaps"):
						coat = r
				road = road or c.roads.has(n)
			if coat.size == Vector2i.ZERO or not road:
				errors.append("air_door: the door at %s is not between a coat-heap chamber and a road" % door)
				continue
			var inside: Vector2i = coat.position + coat.size / 2
			var shut: Mine.PathAnswer = c.mine.path_distance(_camp_floor(c), inside, 160.0, false)
			var open: Mine.PathAnswer = c.mine.path_distance(_camp_floor(c), inside, 160.0, true)
			if shut.distance >= 0.0 or open.distance < 0.0:
				errors.append("air_door: the door at %s is not the only way into its chamber (a side passage)" % door)
	if doors == 0:
		errors.append("air_door: no air door")
	return errors


static func _hooks_rubble(c: Ctx) -> Array[String]:
	var errors: Array[String] = []
	var hooks: Array[Vector2i] = []
	for a: Array in c.anchors:
		if str(a[0]) == "timber_hook":
			hooks.append(a[1])
	for raw: Variant in c.roads.keys():
		var t: Vector2i = raw
		var near: bool = false
		for h: Vector2i in hooks:
			if maxi(absi(h.x - t.x), absi(h.y - t.y)) <= HOOK_SPACING:
				near = true
				break
		if not near:
			errors.append("hooks_rubble: road tile %s has no timber hook within %d tiles" % [t, HOOK_SPACING])
			break
	for ch: Array in c.chambers:
		var r: Rect2i = ch[0]
		var n: int = 0
		for h: Vector2i in hooks:
			if r.has_point(h):
				n += 1
		if n < 2:
			errors.append("hooks_rubble: the chamber at %s has %d hooks; 2 or more" % [r.position, n])
	for cell: Vector2i in c.cells:
		var n: int = 0
		for a: Array in c.anchors:
			var anchor_cell: Vector2i = a[5]
			if str(a[0]) == "rubble_heap" and anchor_cell == cell:
				n += 1
		if n < 1 or n > 2:
			errors.append("hooks_rubble: cell %s has %d rubble heaps; 1-2" % [cell, n])
	return errors


static func _landmarks(c: Ctx) -> Array[String]:
	var errors: Array[String] = []
	var kinds: Dictionary = {}
	for cell: Vector2i in c.cells:
		var here: Array[String] = []
		for a: Array in c.anchors:
			var anchor_cell: Vector2i = a[5]
			if str(a[0]) == "landmark" and anchor_cell == cell:
				here.append(str(a[4]))
		if here.size() != 1:
			errors.append("landmarks: cell %s has %d landmarks; one" % [cell, here.size()])
			continue
		if kinds.has(here[0]):
			errors.append("landmarks: %s repeats in cell %s" % [here[0], cell])
		kinds[here[0]] = true
	return errors


static func _ring(c: Ctx) -> Array[String]:
	for cell: Vector2i in c.cells:
		for y: int in WorldIds.CELL_TILES:
			for x: int in WorldIds.CELL_TILES:
				var t: Vector2i = WorldCoords.tile_of(cell, Vector2i(x, y))
				if WorldCoords.ring_of_tile(t) != 0:
					return ["ring: tile %s is ring %d; every maze tile is ring 0" % [t, WorldCoords.ring_of_tile(t)]] as Array[String]
	return [] as Array[String]


static func _nothing_else(c: Ctx) -> Array[String]:
	var errors: Array[String] = []
	for a: Array in c.anchors:
		if FORBIDDEN.has(str(a[0])):
			errors.append("nothing_else: a %s anchor at %s (no gas, traps, collapses or points of interest)" % [a[0], a[1]])
	return errors
