class_name Basecamp
extends RefCounted
## GEN-02: base camp, cell (0, 0). One authored layout (data/maps/basecamp/cell_0_0.json, GEN-01's
## cell format) with its blind side to the north, rotated by 90-degree steps about the shaft centre
## (10.0, 10.0) to the seed's blind side: tiles, zones, anchors (positions and facings), gate
## barriers and Road Graph portals alike. The winder's alcove backs onto the blind side; the other
## three sides each hold a 3-wide steel gate onto a main-road arm. Brick arches run
## basecamp.arch_length_tiles past each gate (apply_gate_arches, for this cell and the cells the
## gate roads enter). Server-only: the seed, the blind side and the anchors never reach a client.

## LFT-10: base camp's collapse alternate that is the open shaft (the deck's tiles turned to steel).
const OPEN_SHAFT_COLLAPSE: int = 900
const SOURCE: String = "res://data/maps/basecamp/cell_0_0.json"
const SIDES: Array[String] = ["north", "east", "south", "west"]
const FACINGS: Array[String] = ["N", "E", "S", "W"]
## Outward directions by side.
const OUTWARD: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const N: int = 20
const BASE_CAMP_ZONE: int = 1
const FLOOR_CHARS: String = ".=~"
const SOLID_CHARS: String = "#cT"

static var _canonical: Dictionary = {}


## The seed's blind side, 0-3 (north, east, south, west), equally weighted (gen.basecamp).
static func blind_side(run_seed: int) -> int:
	var h: int = LbHash.hash(run_seed, HashDomain.GEN_BASECAMP, PackedInt64Array([0]))
	return posmod(h, 4)


## The authored layout (blind side north), parsed once.
static func canonical() -> Dictionary:
	if _canonical.is_empty():
		_canonical = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(SOURCE)))
	return _canonical


## The cell file for this seed (or for an explicit blind side, M1's map override), in GEN-01's
## format: the canonical layout turned clockwise once per step from north to the blind side, each
## gate then on its main-road axis (recentre_gates).
static func cell_dict(run_seed: int, side: int = -1) -> Dictionary:
	return recentre_gates(rotate(canonical(), blind_side(run_seed) if side < 0 else side))


## Every gate on tiles 9-11 of its edge, the main-road axis (GEN-05's socket at offset 10, GEN-07's
## roads). A quarter turn mirrors two sides' tile order (19 - i), so a gate on 9-11 can land on
## 8-10; that gate's strip (the tiles from the edge in to the gate, 7-11 along it), its zones,
## barrier and portal tiles and its levers move one tile along the edge.
static func recentre_gates(file: Dictionary) -> Dictionary:
	var out: Dictionary = file.duplicate(true)
	for raw: Variant in Variants.array(out.get("barriers", [])):
		var b: Dictionary = Variants.dict(raw)
		var tiles: Array[Vector2i] = []
		for i: Variant in Variants.array(b["tiles"]):
			tiles.append(Vector2i(int(Variants.number(i)) % N, int(Variants.number(i)) / N))
		var s: int = _side_of(tiles)
		var lo: int = N
		var hi: int = -1
		var depth: int = 0
		for t: Vector2i in tiles:
			var ad: Vector2i = _along_depth(t, s)
			lo = mini(lo, ad.x)
			hi = maxi(hi, ad.x)
			depth = maxi(depth, ad.y)
		if lo != 8 or hi != 10:
			continue
		var rows: Array = Variants.array(out["tiles"])
		var zones: Array = Variants.array(out["zones"])
		for d: int in depth + 1:
			for a: int in [12, 11, 10, 9, 8]:
				var from: Vector2i = _tile_at(a - 1, d, s)
				var to: Vector2i = _tile_at(a, d, s)
				var row: String = rows[to.y]
				row[to.x] = str(rows[from.y])[from.x]
				rows[to.y] = row
				var zone_to: Array = Variants.array(zones[to.y])
				var zone_from: Array = Variants.array(zones[from.y])
				zone_to[to.x] = zone_from[from.x]
		var moved: Callable = func(index: Variant) -> int:
			var t: Vector2i = Vector2i(int(Variants.number(index)) % N, int(Variants.number(index)) / N)
			var ad: Vector2i = _along_depth(t, s)
			if ad.y <= depth and ad.x >= 7 and ad.x <= 11:
				t = _tile_at(ad.x + 1, ad.y, s)
			return t.y * N + t.x
		b["tiles"] = Variants.array(b["tiles"]).map(moved)
		var graph: Dictionary = Variants.dict(out.get("road_graph", {}))
		for p: Variant in Variants.array(graph.get("portals", [])):
			var portal: Dictionary = Variants.dict(p)
			if int(Variants.number(portal.get("barrier", 0))) == int(Variants.number(b["id"])):
				portal["tiles"] = Variants.array(portal["tiles"]).map(moved)
		for a: Variant in Variants.array(out.get("anchors", [])):
			var anchor: Dictionary = Variants.dict(a)
			if Variants.array(anchor.get("tags", [])).has("gate:" + SIDES[s]):
				var at: Vector2i = Vector2i(int(Variants.number(anchor["x"])), int(Variants.number(anchor["y"])))
				var ad: Vector2i = _along_depth(at, s)
				var to: Vector2i = _tile_at(ad.x + 1, ad.y, s)
				anchor["x"] = to.x
				anchor["y"] = to.y
	return out


## A tile's place relative to side `s`: x along the edge (west to east, north to south), y in from it.
static func _along_depth(t: Vector2i, s: int) -> Vector2i:
	match s:
		0:
			return Vector2i(t.x, t.y)
		1:
			return Vector2i(t.y, N - 1 - t.x)
		2:
			return Vector2i(t.x, N - 1 - t.y)
	return Vector2i(t.y, t.x)


static func _tile_at(along: int, depth: int, s: int) -> Vector2i:
	match s:
		0:
			return Vector2i(along, depth)
		1:
			return Vector2i(N - 1 - depth, along)
		2:
			return Vector2i(along, N - 1 - depth)
	return Vector2i(depth, along)


static func cell_data(run_seed: int, side: int = -1) -> LbCellData:
	var file: Dictionary = cell_dict(run_seed, side)
	# LFT-10: the open shaft the cage leaves behind. Its deck's tiles stand as floor; at departure
	# Cage swaps in the shaft's guard steel, so the deck site is never boarded again.
	var deck: Rect2i = deck_rect(run_seed, side)
	var standing: Array = []
	var fallen: Array = []
	for y: int in range(deck.position.y, deck.end.y):
		for x: int in range(deck.position.x, deck.end.x):
			standing.append([y * N + x, "."])
			fallen.append([y * N + x, "S"])
	var collapses: Array = Variants.array(file.get("collapses", [])).duplicate()
	collapses.append({"id": OPEN_SHAFT_COLLAPSE, "standing": standing, "fallen": fallen, "is_fallen": false})
	file["collapses"] = collapses
	return CellFile.from_dict(file, "basecamp")


## The layout turned clockwise `steps` quarter turns about the cell centre: (x, y) -> (19 - y, x).
static func rotate(file: Dictionary, steps: int) -> Dictionary:
	var out: Dictionary = file.duplicate(true)
	for _i: int in posmod(steps, 4):
		out = _quarter(out)
	return out


static func _quarter(file: Dictionary) -> Dictionary:
	var rows: Array = Variants.array(file["tiles"])
	var zones: Array = Variants.array(file["zones"])
	var new_rows: Array = []
	var new_zones: Array = []
	for y: int in N:
		var row: String = ""
		var zone_row: Array = []
		for x: int in N:
			# The tile landing at (x, y) came from (y, 19 - x).
			row += str(rows[N - 1 - x])[y]
			zone_row.append(Variants.array(zones[N - 1 - x])[y])
		new_rows.append(row)
		new_zones.append(zone_row)
	var out: Dictionary = file.duplicate(true)
	out["tiles"] = new_rows
	out["zones"] = new_zones
	var anchors: Array = []
	for raw: Variant in Variants.array(file.get("anchors", [])):
		var a: Dictionary = Variants.dict(raw).duplicate(true)
		var x: int = int(Variants.number(a["x"]))
		var y: int = int(Variants.number(a["y"]))
		var w: int = int(Variants.number(a.get("w", 1)))
		var h: int = int(Variants.number(a.get("h", 1)))
		a["x"] = N - y - h
		a["y"] = x
		a["w"] = h
		a["h"] = w
		var tags: Array = []
		for tag: Variant in Variants.array(a.get("tags", [])):
			var t: String = str(tag)
			if t.begins_with("facing:"):
				t = "facing:" + FACINGS[(FACINGS.find(t.substr(7)) + 1) % 4]
			elif t.begins_with("gate:"):
				t = "gate:" + SIDES[(SIDES.find(t.substr(5)) + 1) % 4]
			tags.append(t)
		a["tags"] = tags
		anchors.append(a)
	out["anchors"] = anchors
	var barriers: Array = []
	for raw: Variant in Variants.array(file.get("barriers", [])):
		var b: Dictionary = Variants.dict(raw).duplicate(true)
		b["tiles"] = _rotate_indices(Variants.array(b["tiles"]))
		barriers.append(b)
	out["barriers"] = barriers
	var graph: Dictionary = Variants.dict(file.get("road_graph", {})).duplicate(true)
	var portals: Array = []
	for raw: Variant in Variants.array(graph.get("portals", [])):
		var p: Dictionary = Variants.dict(raw).duplicate(true)
		p["tiles"] = _rotate_indices(Variants.array(p["tiles"]))
		portals.append(p)
	graph["portals"] = portals
	out["road_graph"] = graph
	return out


static func _rotate_indices(indices: Array) -> Array:
	var out: Array = []
	for raw: Variant in indices:
		var i: int = int(Variants.number(raw))
		var x: int = i % N
		var y: int = i / N
		out.append(x * N + (N - 1 - y))
	return out


## The three gates: side, world tiles, outward direction, barrier id and lever positions.
static func gate_specs(run_seed: int, side: int = -1) -> Array[Dictionary]:
	var file: Dictionary = cell_dict(run_seed, side)
	var levers: Dictionary = {}
	for a: Dictionary in fixture_from(file, "gate_lever"):
		var tags: Array = a["tags"]
		for tag: Variant in tags:
			if str(tag).begins_with("gate:"):
				var lever: Dictionary = levers.get(str(tag).substr(5), {})
				lever["inside" if tags.has("inside") else "outside"] = a["position"]
				levers[str(tag).substr(5)] = lever
	var out: Array[Dictionary] = []
	for raw: Variant in Variants.array(file["barriers"]):
		var b: Dictionary = Variants.dict(raw)
		var tiles: Array[Vector2i] = []
		for i: Variant in Variants.array(b["tiles"]):
			tiles.append(Vector2i(int(Variants.number(i)) % N, int(Variants.number(i)) / N))
		var s: int = _side_of(tiles)
		out.append({"side": SIDES[s], "tiles": tiles, "outward": OUTWARD[s], "barrier": int(Variants.number(b["id"])),
			"levers": levers.get(SIDES[s], {}), "socket": "open"})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return SIDES.find(str(a["side"])) < SIDES.find(str(b["side"])))
	return out


## The forced sockets of cell (0, 0)'s edges for GEN-05: the gate sides open, the blind side shut.
static func forced_sockets(run_seed: int, side: int = -1) -> Dictionary:
	var blind: int = blind_side(run_seed) if side < 0 else side
	var out: Dictionary = {}
	for s: int in 4:
		out[SIDES[s]] = "shut" if s == blind else "open"
	return out


## GEN-05's forced sockets for cell (0, 0), as sockets: {side: {open, offset, width}}. Each gate's
## opening is read from the rotated layout's edge tiles (o - floor(w / 2) is the first, GEN-05's
## opening rule); the blind side is shut.
static func gate_sockets(run_seed: int, side: int = -1) -> Dictionary:
	var rows: Array = Variants.array(cell_dict(run_seed, side)["tiles"])
	var out: Dictionary = {}
	for s: int in 4:
		var along: Array[int] = []
		for i: int in N:
			var at: Vector2i = _tile_at(i, 0, s)
			if FLOOR_CHARS.contains(str(rows[at.y])[at.x]):
				along.append(i)
		if along.is_empty():
			out[SIDES[s]] = {"open": false, "offset": 0, "width": 0}
		else:
			out[SIDES[s]] = {"open": true, "offset": along[0] + along.size() / 2, "width": along.size()}
	return out


## Base camp's floor (the deck included), never the arches.
static func inside_tiles(run_seed: int, side: int = -1) -> Dictionary:
	var zones: Array = Variants.array(cell_dict(run_seed, side)["zones"])
	var out: Dictionary = {}
	for y: int in N:
		for x: int in N:
			if int(Variants.number(Variants.array(zones[y])[x])) == BASE_CAMP_ZONE:
				out[Vector2i(x, y)] = true
	return out


static func is_inside_base_camp(run_seed: int, tile: Vector2i, side: int = -1) -> bool:
	return inside_tiles(run_seed, side).has(tile)


## The anchors of one fixture: [{position, size, facing, tags}], by kind basecamp.<name>.
static func fixture(run_seed: int, name: String, side: int = -1) -> Array[Dictionary]:
	return fixture_from(cell_dict(run_seed, side), name)


static func fixture_from(file: Dictionary, name: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw: Variant in Variants.array(file.get("anchors", [])):
		var a: Dictionary = Variants.dict(raw)
		if str(a.get("kind", "")) != "basecamp." + name:
			continue
		var facing: String = ""
		for tag: Variant in Variants.array(a.get("tags", [])):
			if str(tag).begins_with("facing:"):
				facing = str(tag).substr(7)
		out.append({"position": Vector2i(int(Variants.number(a["x"])), int(Variants.number(a["y"]))),
			"size": Vector2i(int(Variants.number(a.get("w", 1))), int(Variants.number(a.get("h", 1)))), "facing": facing,
			"tags": Variants.array(a.get("tags", []))})
	return out


## The cage deck's tiles, as a rect in world tiles.
static func deck_rect(run_seed: int, side: int = -1) -> Rect2i:
	var deck: Dictionary = fixture(run_seed, "cage_deck", side)[0]
	var at: Vector2i = deck["position"]
	var size: Vector2i = deck["size"]
	return Rect2i(at, size)


## How far a point on the deck is from its nearest side (CRT-09: only a 1 x 2 middle lies more
## than tapper.reach_tiles from every side).
static func deck_side_distance(run_seed: int, p: Vector2, side: int = -1) -> float:
	var r: Rect2i = deck_rect(run_seed, side)
	return minf(minf(p.x - r.position.x, r.end.x - p.x), minf(p.y - r.position.y, r.end.y - p.y))


## The shaft wall at a depth: brick-lined down to lift.shaft_brick_above_m, bare rock below.
static func shaft_lining_at(depth_m: float) -> int:
	return WorldIds.TileMaterial.BRICK if depth_m <= Tuning.f(&"lift.shaft_brick_above_m") else WorldIds.TileMaterial.ROCK


## GEN-02's arch rule for `cell` (base camp's own, or one a gate road enters): every solid tile
## 8-adjacent to an arch tile becomes brick. An arch tile is road floor within
## basecamp.arch_length_tiles (by path, branches included) of a gate's outer face, measured away
## from base camp. `rows` are that cell's tile rows; returns them with the rule applied.
static func apply_gate_arches(run_seed: int, cell: Vector2i, rows: PackedStringArray, side: int = -1) -> PackedStringArray:
	var arch: Dictionary = arch_tiles(run_seed, cell, rows, side)
	var out: PackedStringArray = rows.duplicate()
	for y: int in N:
		var row: String = out[y]
		for x: int in N:
			if SOLID_CHARS.contains(row[x]) and _touches(arch, cell * N + Vector2i(x, y)):
				row[x] = "B"
		out[y] = row
	return out


## Every rock (or coal, or timber) tile in `cell` that touches an arch tile: empty when the rule holds.
static func check_gate_arches(run_seed: int, cell: Vector2i, rows: PackedStringArray, side: int = -1) -> Array[String]:
	var arch: Dictionary = arch_tiles(run_seed, cell, rows, side)
	var errors: Array[String] = []
	for y: int in N:
		for x: int in N:
			var w: Vector2i = cell * N + Vector2i(x, y)
			if SOLID_CHARS.contains(rows[y][x]) and _touches(arch, w):
				errors.append("%s is %s beside an arch tile, not brick" % [w, rows[y][x]])
	return errors


## The arch tiles (world) reaching into `cell`: a flood over road floor from each gate's first
## outside tile, through base camp's cell and `cell`, never back into base camp.
static func arch_tiles(run_seed: int, cell: Vector2i, rows: PackedStringArray, side: int = -1) -> Dictionary:
	var grid: Dictionary = {}
	var camp: Array = Variants.array(cell_dict(run_seed, side)["tiles"])
	for y: int in N:
		for x: int in N:
			grid[Vector2i(x, y)] = str(camp[y])[x]
	if cell != Vector2i.ZERO:
		for y: int in N:
			for x: int in N:
				grid[cell * N + Vector2i(x, y)] = rows[y][x]
	var inside: Dictionary = inside_tiles(run_seed, side)
	var length: int = roundi(Tuning.f(&"basecamp.arch_length_tiles"))
	var dist: Dictionary = {}
	var queue: Array[Vector2i] = []
	for g: Dictionary in gate_specs(run_seed, side):
		var outward: Vector2i = g["outward"]
		for t: Vector2i in Variants.array(g["tiles"]):
			var first: Vector2i = t + outward
			if FLOOR_CHARS.contains(str(grid.get(first, "#"))) and not dist.has(first):
				dist[first] = 1
				queue.append(first)
	while not queue.is_empty():
		var t: Vector2i = queue.pop_front()
		var d: int = dist[t]
		if d >= length:
			continue
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = t + step
			if dist.has(n) or inside.has(n) or not FLOOR_CHARS.contains(str(grid.get(n, "#"))):
				continue
			dist[n] = d + 1
			queue.append(n)
	return dist


static func _touches(arch: Dictionary, w: Vector2i) -> bool:
	for dy: int in [-1, 0, 1]:
		for dx: int in [-1, 0, 1]:
			if (dx != 0 or dy != 0) and arch.has(w + Vector2i(dx, dy)):
				return true
	return false


static func _side_of(tiles: Array[Vector2i]) -> int:
	var c: Vector2 = Vector2.ZERO
	for t: Vector2i in tiles:
		c += Vector2(t) + Vector2(0.5, 0.5)
	c /= tiles.size()
	var d: Vector2 = c - Vector2(10.0, 10.0)
	if absf(d.x) > absf(d.y):
		return 1 if d.x > 0.0 else 3
	return 2 if d.y > 0.0 else 0
