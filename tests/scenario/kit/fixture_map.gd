extends RefCounted
## FND-09's fixtures: a picture of a mine as ASCII rows, turned into fixed cells for GEN-01's
## loader, or a named map from data/maps/ (GEN-02's base camp, GEN-03's grey box, "test").
##
## Default legend: '.' floor, '#' rock, 'C' coal, 'B' brick, 'T' timber, 'G' gate (shut),
## 'D' air door (shut). Any lowercase letter or digit is floor with a named spot, for
## placing miners: spot("a"). Rows shorter than the widest are padded with rock, and the
## picture is cut into 20 x 20 cells from tile (0, 0).
##
## SND-01's Road Graph block is derived: each 4-connected floor region of a cell is a road
## zone, and each gate or air-door group joining two zones is a portal over its barrier.

const Self = preload("res://tests/scenario/kit/fixture_map.gd")
const FLOOR: Array[String] = [".", "=", "~"]
const BARRIERS: Array[String] = ["S", "s", "D", "d"]
const DEFAULT_LEGEND: Dictionary = {".": ".", "#": "#", "C": "c", "B": "B", "T": "T", "G": "S", "D": "D"}

var map_name: String = ""
var rows: PackedStringArray = PackedStringArray()
var legend: Dictionary = {}
## Cell files as dictionaries (CellFile's schema).
var cells: Array[Dictionary] = []
## barrier id -> [cell, tile indices]: every 4-connected group of gate or air-door tiles is one
## barrier, numbered from 1 in scan order, cell by cell (set_gate opens and shuts either).
var gates: Dictionary = {}
var _spots: Dictionary = {}


static func from_ascii(picture: PackedStringArray, extra_legend: Dictionary = {}) -> Self:
	var fixture: Self = Self.new()
	fixture._build(picture, extra_legend)
	return fixture


static func named(name: String) -> Self:
	var fixture: Self = Self.new()
	fixture.map_name = name
	return fixture


## A text form that rebuilds this fixture (stored in replay files).
func spec() -> String:
	if not map_name.is_empty():
		return "named:" + map_name
	return "ascii:" + JSON.stringify({"rows": Array(rows), "legend": legend})


static func from_spec(text: String) -> Self:
	if text.is_empty():
		return null
	if text.begins_with("named:"):
		return named(text.substr(6))
	var parsed: Dictionary = Variants.dict(JSON.parse_string(text.substr(6)))
	var picture: PackedStringArray = PackedStringArray(Variants.array(parsed.get("rows", [])))
	return from_ascii(picture, Variants.dict(parsed.get("legend", {})))


## The tile marked with a spot letter or digit.
func spot(mark: String) -> Vector2i:
	if not _spots.has(mark):
		push_error("FixtureMap: no spot '%s'" % mark)
		return Vector2i(-1, -1)
	var tile: Vector2i = _spots[mark]
	return tile


## Commits every cell into a mine; returns how many.
func load_into(mine: Mine) -> int:
	if not map_name.is_empty():
		return mine.load_fixed_map(map_name)
	var count: int = 0
	for file: Dictionary in cells:
		var data: LbCellData = CellFile.from_dict(file, "fixture")
		if data == null:
			return -1
		mine.native.commit(data)
		count += 1
	return count


func _build(picture: PackedStringArray, extra_legend: Dictionary) -> void:
	rows = picture
	legend = extra_legend
	var map: Dictionary = DEFAULT_LEGEND.duplicate()
	map.merge(extra_legend, true)
	var width: int = 0
	for row: String in picture:
		width = maxi(width, row.length())
	var size: int = WorldIds.CELL_TILES
	var cells_x: int = maxi(1, ceili(float(width) / size))
	var cells_y: int = maxi(1, ceili(float(picture.size()) / size))
	var grid: Array[PackedStringArray] = []
	for y: int in cells_y * size:
		var line: PackedStringArray = PackedStringArray()
		var source: String = picture[y] if y < picture.size() else ""
		for x: int in cells_x * size:
			var mark: String = source[x] if x < source.length() else "#"
			var tile_char: String = ""
			if map.has(mark):
				tile_char = str(map[mark])
			elif _is_spot(mark):
				tile_char = "."
				_spots[mark] = Vector2i(x, y)
			else:
				push_error("FixtureMap: unknown mark '%s' at (%d, %d)" % [mark, x, y])
				tile_char = "#"
			line.append(tile_char)
		grid.append(line)
	var next_gate: int = 1
	for cy: int in cells_y:
		for cx: int in cells_x:
			var tiles: Array[String] = []
			var zones: Array = []
			for y: int in size:
				tiles.append("".join(grid[cy * size + y].slice(cx * size, cx * size + size)))
				var zone_row: Array[int] = []
				zone_row.resize(size)
				zones.append(zone_row)
			var barriers: Array = []
			var portals: Array = []
			var zone_count: int = _assign_zones(tiles, zones)
			for group: PackedInt32Array in _gate_groups(tiles):
				var kind: String = "gate" if tiles[group[0] / size][group[0] % size] in ["S", "s"] else "air_door"
				var open: bool = tiles[group[0] / size][group[0] % size] in ["s", "d"]
				var joined: PackedInt32Array = _zones_beside(group, zones)
				var portal_id: int = 0
				if joined.size() >= 2:
					portal_id = portals.size() + 1
					portals.append({"id": portal_id, "kind": kind, "a": joined[0], "b": joined[1], "barrier": next_gate, "tiles": Array(group)})
				barriers.append({"id": next_gate, "portal": portal_id, "tiles": Array(group), "open": open})
				gates[next_gate] = [Vector2i(cx, cy), group]
				next_gate += 1
			var zone_list: Array = []
			for z: int in range(1, zone_count + 1):
				zone_list.append({"id": z, "kind": "road"})
			var cell: Dictionary = {"format": CellFile.FORMAT, "cell": [cx, cy], "tiles": tiles, "zones": zones, "barriers": barriers}
			if zone_count > 0:
				cell["road_graph"] = {"zones": zone_list, "portals": portals}
			cells.append(cell)


static func _is_spot(mark: String) -> bool:
	return mark.length() == 1 and ((mark >= "a" and mark <= "z") or (mark >= "0" and mark <= "9"))


## Numbers each 4-connected floor region of a cell from 1; returns how many.
static func _assign_zones(tiles: Array[String], zones: Array) -> int:
	var size: int = WorldIds.CELL_TILES
	var next: int = 0
	for y: int in size:
		for x: int in size:
			var row: Array[int] = zones[y]
			if row[x] != 0 or not tiles[y][x] in FLOOR:
				continue
			next += 1
			var stack: Array[Vector2i] = [Vector2i(x, y)]
			row[x] = next
			while not stack.is_empty():
				var at: Vector2i = stack.pop_back()
				for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = at + step
					if n.x < 0 or n.y < 0 or n.x >= size or n.y >= size:
						continue
					var n_row: Array[int] = zones[n.y]
					if n_row[n.x] == 0 and tiles[n.y][n.x] in FLOOR:
						n_row[n.x] = next
						stack.append(n)
	return next


## The zones touching a group of portal tiles, ascending.
static func _zones_beside(group: PackedInt32Array, zones: Array) -> PackedInt32Array:
	var size: int = WorldIds.CELL_TILES
	var found: Dictionary = {}
	for index: int in group:
		var at: Vector2i = Vector2i(index % size, index / size)
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = at + step
			if n.x < 0 or n.y < 0 or n.x >= size or n.y >= size:
				continue
			var row: Array[int] = zones[n.y]
			if row[n.x] != 0:
				found[row[n.x]] = true
	var out: PackedInt32Array = PackedInt32Array(found.keys())
	out.sort()
	return out


## 4-connected groups of gate or air-door tiles (shut or open) in one cell, as local indices.
static func _gate_groups(tiles: Array[String]) -> Array[PackedInt32Array]:
	var size: int = WorldIds.CELL_TILES
	var seen: Dictionary = {}
	var groups: Array[PackedInt32Array] = []
	for y: int in size:
		for x: int in size:
			if not tiles[y][x] in BARRIERS or seen.has(y * size + x):
				continue
			var group: PackedInt32Array = PackedInt32Array()
			var stack: Array[Vector2i] = [Vector2i(x, y)]
			seen[y * size + x] = true
			while not stack.is_empty():
				var at: Vector2i = stack.pop_back()
				group.append(at.y * size + at.x)
				for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var next: Vector2i = at + step
					if next.x < 0 or next.y < 0 or next.x >= size or next.y >= size:
						continue
					if tiles[next.y][next.x] == tiles[at.y][at.x] and not seen.has(next.y * size + next.x):
						seen[next.y * size + next.x] = true
						stack.append(next)
			group.sort()
			groups.append(group)
	return groups
