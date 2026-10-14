extends RefCounted
## GEN-03's grey box, authored as text: four cells beyond base camp's gates (blind side west), each a
## 20x20 picture, its chambers, anchors and coal seams. `build()` returns the cell dictionaries in
## GEN-01's file format (CellFile), with Road Graph zones and portals cut by rule:
##   - each declared chamber rectangle is a chamber zone;
##   - a floor tile outside a chamber that touches it is an opening portal (zone 0) to the road;
##   - each remaining 4-connected floor region is a road zone;
##   - each shut air door tile ('D') is a barrier and an air_door portal between the zones it joins.
## The gate roads' brick arches come from GEN-02 (Basecamp.apply_gate_arches). Coordinates in this
## file are local to each cell; placements are world tiles. tools/build/gen_m1_greybox.gd writes it all
## to data/maps/m1_greybox/. QA-01 may rearrange it as long as m1_greybox_check.gd still passes.

const MAP: String = "m1_greybox"
const BLIND_SIDE: int = 3  # west: the gates face north, east and south
const RUN_SEED: int = 20261014

## cell -> {rows, chambers: [[x, y, w, h, tags]], coal: [[x, y, w, h]], anchors: [[type, x, y, w, h, tags, kind]]}
const CELLS: Dictionary = {
	# North: the gate arm runs north (3 wide and railed under the arches, then 2 wide) into the sight
	# line, which opens west into the 7x7 start roost; a 1-wide spur ends in a dead end.
	Vector2i(0, -1): {
		"rows": [
			"####################",
			"#.......############",
			"#.......############",
			"#...................",
			"#.......============",
			"#...................",
			"#.......##..########",
			"#.......##..########",
			"##########..########",
			"##########..########",
			"###.......=.########",
			"#########.=.########",
			"#########.=.########",
			"#########.=.########",
			"#########.=.########",
			"#########.=.########",
			"#########.=.########",
			"#########.=.########",
			"#########.=.########",
			"#########.=.########",
		],
		"chambers": [[1, 1, 7, 7, ["coat_heaps", "roost"]]],
		"coal": [[12, 7, 6, 3], [1, 12, 6, 4]],
		"anchors": [
			["landmark", 11, 12, 1, 1, [], "hand_pump"],
			["rubble_heap", 16, 5, 1, 1, [], ""],
			["timber_hook", 12, 3, 1, 1, ["road"], ""], ["timber_hook", 18, 3, 1, 1, ["road"], ""],
			["timber_hook", 10, 7, 1, 1, ["road"], ""], ["timber_hook", 11, 13, 1, 1, ["road"], ""],
			["timber_hook", 9, 18, 1, 1, ["road"], ""], ["timber_hook", 5, 10, 1, 1, ["road"], ""],
			["timber_hook", 1, 7, 1, 1, ["chamber"], ""], ["timber_hook", 7, 7, 1, 1, ["chamber"], ""],
			["timber_hook", 2, 1, 1, 1, ["rib"], ""], ["timber_hook", 3, 1, 1, 1, ["rib"], ""],
			["timber_hook", 4, 1, 1, 1, ["rib"], ""], ["timber_hook", 5, 1, 1, 1, ["rib"], ""],
			["timber_hook", 6, 1, 1, 1, ["rib"], ""],
		],
	},
	# North-east: the sight line runs on east and turns south (closing the loop through the east
	# cell); a 5-thick pillar parts it from a parallel 2-wide road that ends in the 5x5 chamber, entered
	# at a corner so only its centre is out of the Tapper's reach.
	Vector2i(1, -1): {
		"rows": [
			"####################",
			"####################",
			"####################",
			"...................#",
			"================.=.#",
			"...................#",
			"################.=.#",
			"################.=.#",
			"################.=.#",
			"################.=.#",
			"#.......########.=.#",
			"#.....#............#",
			"#.....#............#",
			"#.....##########.=.#",
			"#.....##########.=.#",
			"################.=.#",
			"################.=.#",
			"################.=.#",
			"################.=.#",
			"################.=.#",
		],
		"chambers": [[1, 10, 5, 5, ["centre_line"]]],
		"coal": [[2, 7, 12, 3], [8, 15, 7, 4]],
		"anchors": [
			["landmark", 14, 12, 1, 1, [], "brattice_sheet"],
			["rubble_heap", 18, 9, 1, 1, [], ""],
			["timber_hook", 0, 3, 1, 1, ["road"], ""], ["timber_hook", 6, 3, 1, 1, ["road"], ""],
			["timber_hook", 12, 3, 1, 1, ["road"], ""], ["timber_hook", 16, 9, 1, 1, ["road"], ""],
			["timber_hook", 16, 15, 1, 1, ["road"], ""], ["timber_hook", 8, 11, 1, 1, ["road"], ""],
			["timber_hook", 1, 10, 1, 1, ["chamber"], ""], ["timber_hook", 5, 14, 1, 1, ["chamber"], ""],
			["rich_rock", 7, 6, 9, 5, [], ""],
			# GEN-03's voice pairs (criterion 2): road tiles with only 2 tiles of rock between, and 3+.
			["wall_fixture", 10, 5, 1, 1, ["to:10,11"], "m1.voice_thick"],
		],
	},
	# East: the gate arm runs east to meet the loop road; beyond the arches a 1-wide passage, 2 tiles
	# of rock below the arm, ends in a dead end; a side passage through the air door leads to the 8x6
	# hoard.
	Vector2i(1, 0): {
		"rows": [
			"################.=.#",
			"################.=.#",
			"################.=.#",
			"################.=.#",
			"################.=.#",
			"################.=.#",
			"################.=.#",
			"################.=.#",
			"...................#",
			"================.=.#",
			"...................#",
			"#####.###########.##",
			"#####D###########.##",
			"#........##.......##",
			"#........###########",
			"#........###########",
			"#........###########",
			"#........###########",
			"#........###########",
			"####################",
		],
		"chambers": [[1, 13, 8, 6, ["coat_heaps", "hoard"]]],
		"coal": [[1, 2, 13, 4], [11, 15, 8, 3]],
		"anchors": [
			["landmark", 6, 10, 1, 1, [], "chalked_date"],
			["rubble_heap", 14, 8, 1, 1, [], ""],
			["timber_hook", 3, 8, 1, 1, ["road"], ""], ["timber_hook", 9, 10, 1, 1, ["road"], ""],
			["timber_hook", 15, 10, 1, 1, ["road"], ""], ["timber_hook", 16, 2, 1, 1, ["road"], ""],
			["timber_hook", 12, 13, 1, 1, ["road"], ""], ["timber_hook", 17, 12, 1, 1, ["road"], ""],
			["timber_hook", 8, 13, 1, 1, ["chamber"], ""], ["timber_hook", 8, 18, 1, 1, ["chamber"], ""],
			["timber_hook", 1, 13, 1, 1, ["rib"], ""], ["timber_hook", 1, 14, 1, 1, ["rib"], ""],
			["timber_hook", 1, 16, 1, 1, ["rib"], ""], ["timber_hook", 1, 17, 1, 1, ["rib"], ""],
			["rich_rock", 0, 0, 16, 7, [], ""],
			["wall_fixture", 13, 13, 1, 1, ["to:13,10"], "m1.voice_thin"],
		],
	},
	# South: the gate arm, 10 tiles 3 wide under the arches, ends in a stall; a 2-wide road west, a
	# 1-wide one down, a 2-wide one along and back up and in to the deepest chamber, 7x7; a 5-thick
	# rich mass between the two.
	Vector2i(0, 1): {
		"rows": [
			"#########.=.########",
			"#########.=.########",
			"#########.=.########",
			"#########.=.########",
			"#.........=.########",
			"#.........=.########",
			"#.#######.=.########",
			"#.#######.=.########",
			"#.#######.=.########",
			"#.#######.=.########",
			"#.##################",
			"#.#####............#",
			"#.#####............#",
			"#.#####..###.......#",
			"#.#####..###.......#",
			"#.#####..###.......#",
			"#.#####..###.......#",
			"#........###.......#",
			"#........###########",
			"####################",
		],
		"chambers": [[12, 11, 7, 7, ["deepest"]]],
		"coal": [[2, 6, 5, 4], [12, 18, 7, 1]],
		"anchors": [
			["landmark", 3, 5, 1, 1, [], "broken_tub"],
			["rubble_heap", 6, 4, 1, 1, [], ""], ["rubble_heap", 1, 12, 1, 1, [], ""],
			["timber_hook", 9, 2, 1, 1, ["road"], ""], ["timber_hook", 4, 4, 1, 1, ["road"], ""],
			["timber_hook", 1, 9, 1, 1, ["road"], ""], ["timber_hook", 1, 15, 1, 1, ["road"], ""],
			["timber_hook", 5, 17, 1, 1, ["road"], ""], ["timber_hook", 8, 14, 1, 1, ["road"], ""],
			["timber_hook", 9, 11, 1, 1, ["road"], ""], ["timber_hook", 11, 8, 1, 1, ["road"], ""],
			["timber_hook", 12, 11, 1, 1, ["chamber"], ""], ["timber_hook", 18, 17, 1, 1, ["chamber"], ""],
			["rich_rock", 2, 6, 5, 11, [], ""],
		],
	},
}

## World tiles.
const PLACEMENTS: Dictionary = {
	"format": 1,
	"note": "GEN-03's defaults; QA-01 owns them. World tiles. Coat heaps hang on the coat chambers' rib hooks.",
	"creatures": [
		{"kind": "MOTH", "tile": [4, -19], "note": "asleep at the start roost"},
		{"kind": "TAPPER", "tile": [28, -12], "note": "in the north-east pillar, the rich rock farthest from the gates"},
	],
	"coat_heaps": [[2, -19], [3, -19], [5, -19], [6, -19], [21, 13], [21, 14], [21, 16], [21, 17]],
	"items": [
		{"kind": "FUSE", "tile": [31, 13], "note": "the east dead end"},
		{"kind": "MAGNETO", "tile": [23, -8], "note": "the 5x5 chamber"},
		{"kind": "ROPE_CLAMP", "tile": [16, 31], "note": "the deepest chamber"},
		{"kind": "GAUZE_LAMP", "tile": [4, -10], "oil": 0.5, "notches": 1, "note": "the north spur's dead end"},
		{"kind": "GAUZE_LAMP", "tile": [10, 27], "oil": 0.3, "notches": 2, "note": "the south stall"},
		{"kind": "OIL_FLASK", "tile": [30, -8], "note": "the parallel road"},
		{"kind": "OIL_FLASK", "tile": [33, 9], "note": "the east arm"},
	],
}


## The manifest, cells (cell -> CellFile dictionary) and placements.
static func build() -> Dictionary:
	var cells: Dictionary = {}
	for raw: Variant in CELLS.keys():
		var cell: Vector2i = raw
		var spec: Dictionary = CELLS[raw]
		cells[cell] = cell_dict(cell, spec)
	var manifest: Dictionary = {"format": 1, "name": MAP, "run_seed": str(RUN_SEED), "blind_side": "west",
		"base_camp": [0, 0], "cells": [], "placements": "placements.json",
		"note": "GEN-03's M1 grey box: base camp (blind side west) and four hand-made cells beyond its gates. Edges out of these five cells are shut rock."}
	var order: Array = cells.keys()
	order.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for c: Vector2i in order:
		Variants.array(manifest["cells"]).append([c.x, c.y])
	return {"manifest": manifest, "cells": cells, "placements": PLACEMENTS}


static func cell_dict(cell: Vector2i, spec: Dictionary) -> Dictionary:
	var rows: PackedStringArray = PackedStringArray()
	for r: Variant in Variants.array(spec["rows"]):
		rows.append(str(r))
	for rect: Variant in Variants.array(spec.get("coal", [])):
		var q: Array = rect
		for y: int in range(int(Variants.number(q[1])), int(Variants.number(q[1])) + int(Variants.number(q[3]))):
			var row: String = rows[y]
			for x: int in range(int(Variants.number(q[0])), int(Variants.number(q[0])) + int(Variants.number(q[2]))):
				if row[x] == "#":
					row[x] = "c"
			rows[y] = row
	rows = Basecamp.apply_gate_arches(RUN_SEED, cell, rows, BLIND_SIDE)
	# Zones: chambers first, then openings, then road regions.
	var zone: Array[PackedInt32Array] = []
	for y: int in 20:
		var line: PackedInt32Array = PackedInt32Array()
		line.resize(20)
		zone.append(line)
	var kinds: Array[Dictionary] = []
	var next_id: int = 1
	var anchors: Array = []
	for raw: Variant in Variants.array(spec.get("chambers", [])):
		var ch: Array = raw
		var id: int = next_id
		next_id += 1
		kinds.append({"id": id, "kind": "chamber"})
		for y: int in range(int(Variants.number(ch[1])), int(Variants.number(ch[1])) + int(Variants.number(ch[3]))):
			for x: int in range(int(Variants.number(ch[0])), int(Variants.number(ch[0])) + int(Variants.number(ch[2]))):
				if _floor(rows[y][x]):
					zone[y][x] = id
		anchors.append({"type": "chamber", "x": ch[0], "y": ch[1], "w": ch[2], "h": ch[3], "tags": ch[4], "kind": ""})
	var portals: Array = []
	var next_portal: int = 1
	# Openings: road floor touching a chamber.
	for raw: Variant in Variants.array(spec.get("chambers", [])):
		var ch: Array = raw
		var chamber_zone: int = zone[int(Variants.number(ch[1]))][int(Variants.number(ch[0]))]
		var tiles: Array = []
		for y: int in 20:
			for x: int in 20:
				if not _floor(rows[y][x]) or zone[y][x] != 0:
					continue
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = Vector2i(x, y) + d
					if n.x >= 0 and n.x < 20 and n.y >= 0 and n.y < 20 and zone[n.y][n.x] == chamber_zone:
						tiles.append(y * 20 + x)
						break
		if not tiles.is_empty():
			portals.append({"id": next_portal, "kind": "opening", "a": chamber_zone, "b": -1, "barrier": 0, "tiles": tiles})
			next_portal += 1
	var opening_tiles: Dictionary = {}
	for p: Dictionary in portals:
		for i: Variant in Variants.array(p["tiles"]):
			opening_tiles[int(Variants.number(i))] = true
	# Road regions: 4-connected floor that is neither chamber nor opening.
	for y: int in 20:
		for x: int in 20:
			if not _floor(rows[y][x]) or zone[y][x] != 0 or opening_tiles.has(y * 20 + x):
				continue
			var id: int = next_id
			next_id += 1
			kinds.append({"id": id, "kind": "road"})
			var stack: Array[Vector2i] = [Vector2i(x, y)]
			zone[y][x] = id
			while not stack.is_empty():
				var t: Vector2i = stack.pop_back()
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = t + d
					if n.x < 0 or n.x >= 20 or n.y < 0 or n.y >= 20:
						continue
					if _floor(rows[n.y][n.x]) and zone[n.y][n.x] == 0 and not opening_tiles.has(n.y * 20 + n.x):
						zone[n.y][n.x] = id
						stack.append(n)
	# Each opening's road side.
	for p: Dictionary in portals:
		for i: Variant in Variants.array(p["tiles"]):
			var t: Vector2i = Vector2i(int(Variants.number(i)) % 20, int(Variants.number(i)) / 20)
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = t + d
				if n.x >= 0 and n.x < 20 and n.y >= 0 and n.y < 20:
					var z: int = zone[n.y][n.x]
					if z != 0 and z != int(Variants.number(p["a"])):
						p["b"] = z
	# Air doors: barriers and their portals.
	var barriers: Array = []
	var next_barrier: int = 1
	for y: int in 20:
		for x: int in 20:
			if rows[y][x] != "D" and rows[y][x] != "d":
				continue
			var joined: Array[int] = []
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = Vector2i(x, y) + d
				if n.x >= 0 and n.x < 20 and n.y >= 0 and n.y < 20 and zone[n.y][n.x] != 0 and not joined.has(zone[n.y][n.x]):
					joined.append(zone[n.y][n.x])
			barriers.append({"id": next_barrier, "portal": next_portal, "tiles": [y * 20 + x], "open": rows[y][x] == "d"})
			portals.append({"id": next_portal, "kind": "air_door", "a": joined[0], "b": joined[1], "barrier": next_barrier, "tiles": [y * 20 + x]})
			next_barrier += 1
			next_portal += 1
	for raw: Variant in Variants.array(spec.get("anchors", [])):
		var a: Array = raw
		anchors.append({"type": a[0], "x": a[1], "y": a[2], "w": a[3], "h": a[4], "tags": a[5], "kind": a[6]})
	var zones_out: Array = []
	for line: PackedInt32Array in zone:
		zones_out.append(Array(line))
	return {"format": CellFile.FORMAT, "cell": [cell.x, cell.y], "tiles": Array(rows), "zones": zones_out, "anchors": anchors,
		"barriers": barriers, "collapses": [], "road_graph": {"zones": kinds, "portals": portals}}


static func _floor(c: String) -> bool:
	return c == "." or c == "=" or c == "~"
