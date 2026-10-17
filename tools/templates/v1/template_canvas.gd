class_name TemplateCanvas
extends RefCounted
## GEN-16's drawing board for generated templates: a footprint of tiles (CellFile's characters), its
## anchors, stubs and collapse alternates, drawn by code (TemplateDesignsV1) and handed to
## TemplateScaffold as a spec. Positions are footprint tiles, (0, 0) the north-west corner; a stub's
## opening starts at offset - width / 2 along its edge (GEN-05's rule), its throat the first
## mine.stub_throat_depth_tiles tiles in from the edge.

const CELL: int = 20
const WALKABLE: String = ".=~sSdD"
const FACES: String = "#c"
const THROAT_DEPTH: int = 2
const EDGES: Array[String] = ["north", "east", "south", "west"]

var id: String = ""
var kind: String = "biome_cell"
var biome: String = "seam"
var footprint: Vector2i = Vector2i(1, 1)
var poi_kind: String = ""
var shape: String = ""
var old_fall: bool = false
var weight: float = 1.0
var w: int = CELL
var h: int = CELL
var rows: Array[PackedStringArray] = []
## [type, x, y, w, h, tags, kind]
var anchors: Array = []
## {cell, edge, offset, max_width, depth, door}
var stubs: Array = []
## {id, tiles: [[x, y, char]]}
var collapses: Array = []
## Throat tiles (x, y) -> true: no anchor or collapse goes there.
var throats: Dictionary = {}


func _init(template_id: String, template_kind: String, template_biome: String, size: Vector2i = Vector2i(1, 1)) -> void:
	id = template_id
	kind = template_kind
	biome = template_biome
	footprint = size
	w = size.x * CELL
	h = size.y * CELL
	for y: int in h:
		var row: PackedStringArray = PackedStringArray()
		row.resize(w)
		row.fill("#")
		rows.append(row)


#region Tiles

func inside(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


func at(x: int, y: int) -> String:
	return rows[y][x] if inside(x, y) else "#"


func put(x: int, y: int, ch: String) -> void:
	if inside(x, y):
		var row: PackedStringArray = rows[y]
		row[x] = ch
		rows[y] = row


func rect(x: int, y: int, rw: int, rh: int, ch: String = ".") -> void:
	for yy: int in range(y, y + rh):
		for xx: int in range(x, x + rw):
			put(xx, yy, ch)


func walkable(x: int, y: int) -> bool:
	return inside(x, y) and WALKABLE.contains(at(x, y))


func face(x: int, y: int) -> bool:
	return inside(x, y) and FACES.contains(at(x, y))


func floor_neighbours(x: int, y: int) -> int:
	var n: int = 0
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		n += 1 if walkable(x + d.x, y + d.y) else 0
	return n


func on_edge(x: int, y: int) -> bool:
	return x == 0 or y == 0 or x == w - 1 or y == h - 1

#endregion

#region Stubs and spokes

## The tiles along an edge an opening of `width` at `offset` covers.
static func opening(offset: int, width: int) -> Array[int]:
	var out: Array[int] = []
	for a: int in range(offset - width / 2, offset - width / 2 + width):
		out.append(a)
	return out


## The tile `d` in from `edge` of footprint cell `cell`, `a` along it.
func edge_tile(edge: String, a: int, d: int, cell: Vector2i = Vector2i.ZERO) -> Vector2i:
	var ox: int = cell.x * CELL
	var oy: int = cell.y * CELL
	match edge:
		"north":
			return Vector2i(ox + a, oy + d)
		"south":
			return Vector2i(ox + a, oy + CELL - 1 - d)
		"west":
			return Vector2i(ox + d, oy + a)
	return Vector2i(ox + CELL - 1 - d, oy + a)


## A stub on `edge` and its road `length` tiles in from the edge, `width` wide (the throat first).
func spoke(edge: String, offset: int, width: int, length: int, cell: Vector2i = Vector2i.ZERO, door: bool = false, ch: String = ".") -> void:
	stubs.append({"cell": [cell.x, cell.y], "edge": edge, "offset": offset, "max_width": width, "depth": 0, "door": door})
	for a: int in opening(offset, width):
		for d: int in length:
			var t: Vector2i = edge_tile(edge, a, d, cell)
			put(t.x, t.y, ch)
			if d < THROAT_DEPTH:
				throats[t] = true


## A collapse alternate: `tiles` fall to rock.
func collapse(tiles: Array[Vector2i]) -> void:
	var list: Array = []
	for t: Vector2i in tiles:
		list.append([t.x, t.y, "#"])
	collapses.append({"id": collapses.size() + 1, "tiles": list})


## A collapse across a spoke, `d` tiles in from its edge.
func collapse_across(edge: String, offset: int, width: int, d: int, cell: Vector2i = Vector2i.ZERO) -> void:
	var tiles: Array[Vector2i] = []
	for a: int in opening(offset, width):
		tiles.append(edge_tile(edge, a, d, cell))
	collapse(tiles)

#endregion

#region Anchors

func anchor(type: String, x: int, y: int, aw: int = 1, ah: int = 1, tags: Array = [], anchor_kind: String = "") -> void:
	anchors.append([type, x, y, aw, ah, tags, anchor_kind])


func anchored(x: int, y: int) -> bool:
	for raw: Variant in anchors:
		var a: Array = raw
		var ax: int = a[1]
		var ay: int = a[2]
		var aw: int = a[3]
		var ah: int = a[4]
		if x >= ax and y >= ay and x < ax + aw and y < ay + ah:
			return true
	return false


func count(type: String) -> int:
	var n: int = 0
	for raw: Variant in anchors:
		var a: Array = raw
		n += 1 if str(a[0]) == type else 0
	return n


## A free floor tile for a one-tile anchor: walkable, no throat, not yet anchored, none of
## `around` collapse tiles; the first of `prefer` that fits, else none (Vector2i(-1, -1)).
func free_floor(prefer: Array[Vector2i]) -> Vector2i:
	var falls: Dictionary = _collapse_tiles()
	for t: Vector2i in prefer:
		if walkable(t.x, t.y) and not throats.has(t) and not anchored(t.x, t.y) and not falls.has(t):
			return t
	return Vector2i(-1, -1)


## Every floor tile with at most two floor neighbours (a corner, a stall or a dead end), no throat.
func corners() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y: int in h:
		for x: int in w:
			if walkable(x, y) and not throats.has(Vector2i(x, y)) and floor_neighbours(x, y) <= 2 and floor_neighbours(x, y) >= 1:
				out.append(Vector2i(x, y))
	return out


## Every face tile (rock or coal) beside floor, off the outer edge and off every throat's side.
func faces() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y: int in range(1, h - 1):
		for x: int in range(1, w - 1):
			if not face(x, y) or floor_neighbours(x, y) == 0:
				continue
			var by_throat: bool = false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				by_throat = by_throat or throats.has(Vector2i(x + d.x, y + d.y))
			if not by_throat:
				out.append(Vector2i(x, y))
	return out


## Timber hooks so that every floor tile lies within `reach` tiles by path of one (GEN-04's rule),
## greedily, and one inside every chamber anchor.
func auto_hooks(reach: int) -> void:
	var hooks: Array[Vector2i] = []
	for raw: Variant in anchors:
		var a: Array = raw
		if str(a[0]) == "timber_hook":
			hooks.append(Vector2i(Variants.whole(a[1]), Variants.whole(a[2])))
	for raw: Variant in anchors.duplicate():
		var a: Array = raw
		if str(a[0]) != "chamber":
			continue
		var cx: int = Variants.whole(a[1])
		var cy: int = Variants.whole(a[2])
		var has: bool = false
		for hk: Vector2i in hooks:
			has = has or (hk.x >= cx and hk.y >= cy and hk.x < cx + Variants.whole(a[3]) and hk.y < cy + Variants.whole(a[4]))
		if not has:
			var t: Vector2i = Vector2i(cx + Variants.whole(a[3]) / 2, cy + Variants.whole(a[4]) / 2)
			anchor("timber_hook", t.x, t.y)
			hooks.append(t)
	var covered: Dictionary = {}
	for hk: Vector2i in hooks:
		for t: Vector2i in _reach(hk, reach):
			covered[t] = true
	for y: int in h:
		for x: int in w:
			var t: Vector2i = Vector2i(x, y)
			if not walkable(x, y) or covered.has(t):
				continue
			var best: Vector2i = Vector2i(-1, -1)
			var gain: int = -1
			for c: Vector2i in _reach(t, reach):
				if throats.has(c) or anchored(c.x, c.y):
					continue
				var n: int = 0
				for u: Vector2i in _reach(c, reach):
					n += 0 if covered.has(u) else 1
				if n > gain:
					gain = n
					best = c
			if best.x < 0:
				best = t
			anchor("timber_hook", best.x, best.y)
			for u: Vector2i in _reach(best, reach):
				covered[u] = true


func _reach(from: Vector2i, reach: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = [from]
	var seen: Dictionary = {from: 0}
	var i: int = 0
	while i < out.size():
		var t: Vector2i = out[i]
		i += 1
		var d: int = Variants.whole(seen[t])
		if d >= reach:
			continue
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = t + step
			if walkable(n.x, n.y) and not seen.has(n):
				seen[n] = d + 1
				out.append(n)
	return out


func _collapse_tiles() -> Dictionary:
	var out: Dictionary = {}
	for raw: Variant in collapses:
		var c: Dictionary = raw
		for t: Variant in Variants.array(c["tiles"]):
			var p: Array = t
			out[Vector2i(Variants.whole(p[0]), Variants.whole(p[1]))] = true
	return out

#endregion

## The canvas as TemplateScaffold.from_spec's spec.
func spec() -> Dictionary:
	var text: Array = []
	for row: PackedStringArray in rows:
		text.append("".join(row))
	return {"id": id, "kind": kind, "biome": biome, "footprint": [footprint.x, footprint.y], "poi_kind": poi_kind, "shape": shape,
		"old_fall": old_fall, "weight": weight, "rows": text, "anchors": anchors.duplicate(true), "stubs": stubs.duplicate(true),
		"collapses": collapses.duplicate(true)}


## A one-cell spec turned: `o` quarter turns clockwise (0-3), after mirroring east to west when
## `mirror`. Null when a stub would leave the socket offsets (a 3-wide stub at 10 mirrors to 9).
static func oriented(src: Dictionary, o: int, mirror: bool, new_id: String) -> Variant:
	var map: Callable = func(p: Vector2i) -> Vector2i:
		var q: Vector2i = Vector2i(CELL - 1 - p.x, p.y) if mirror else p
		for _i: int in o:
			q = Vector2i(CELL - 1 - q.y, q.x)
		return q
	var rows_in: Array = Variants.array(src["rows"])
	var out_rows: Array[PackedStringArray] = []
	for y: int in CELL:
		var row: PackedStringArray = PackedStringArray()
		row.resize(CELL)
		out_rows.append(row)
	for y: int in CELL:
		var line: String = str(rows_in[y])
		for x: int in CELL:
			var q: Vector2i = map.call(Vector2i(x, y))
			var row: PackedStringArray = out_rows[q.y]
			row[q.x] = line[x]
			out_rows[q.y] = row
	var text: Array = []
	for row: PackedStringArray in out_rows:
		text.append("".join(row))
	var anchors_out: Array = []
	for raw: Variant in Variants.array(src["anchors"]):
		var a: Array = Variants.array(raw).duplicate(true)
		var p: Vector2i = map.call(Vector2i(Variants.whole(a[1]), Variants.whole(a[2])))
		var q: Vector2i = map.call(Vector2i(Variants.whole(a[1]) + Variants.whole(a[3]) - 1, Variants.whole(a[2]) + Variants.whole(a[4]) - 1))
		a[1] = mini(p.x, q.x)
		a[2] = mini(p.y, q.y)
		a[3] = absi(p.x - q.x) + 1
		a[4] = absi(p.y - q.y) + 1
		anchors_out.append(a)
	var stubs_out: Array = []
	for raw: Variant in Variants.array(src["stubs"]):
		var s: Dictionary = Variants.dict(raw).duplicate(true)
		var width: int = Variants.whole(s["max_width"])
		var tiles: Array[Vector2i] = []
		for a: int in opening(Variants.whole(s["offset"]), width):
			tiles.append(map.call(_edge_tile_of(str(s["edge"]), a)))
		var edge: String = _edge_of(tiles)
		var along: Array[int] = []
		for t: Vector2i in tiles:
			along.append(t.x if edge == "north" or edge == "south" else t.y)
		along.sort()
		var offset: int = along[0] + width / 2
		if edge.is_empty() or not [5, 10, 15].has(offset) or opening(offset, width) != along:
			return null
		s["edge"] = edge
		s["offset"] = offset
		stubs_out.append(s)
	var collapses_out: Array = []
	for raw: Variant in Variants.array(src["collapses"]):
		var c: Dictionary = Variants.dict(raw).duplicate(true)
		var tiles_out: Array = []
		for t: Variant in Variants.array(c["tiles"]):
			var p: Array = t
			var q: Vector2i = map.call(Vector2i(Variants.whole(p[0]), Variants.whole(p[1])))
			tiles_out.append([q.x, q.y, p[2]])
		c["tiles"] = tiles_out
		collapses_out.append(c)
	var out: Dictionary = src.duplicate(true)
	out["id"] = new_id
	out["rows"] = text
	out["anchors"] = anchors_out
	out["stubs"] = stubs_out
	out["collapses"] = collapses_out
	return out


static func _edge_tile_of(edge: String, a: int) -> Vector2i:
	match edge:
		"north":
			return Vector2i(a, 0)
		"south":
			return Vector2i(a, CELL - 1)
		"west":
			return Vector2i(0, a)
	return Vector2i(CELL - 1, a)


static func _edge_of(tiles: Array[Vector2i]) -> String:
	var all_on: Callable = func(test: Callable) -> bool:
		for t: Vector2i in tiles:
			if not test.call(t):
				return false
		return true
	if all_on.call(func(t: Vector2i) -> bool: return t.y == 0):
		return "north"
	if all_on.call(func(t: Vector2i) -> bool: return t.y == CELL - 1):
		return "south"
	if all_on.call(func(t: Vector2i) -> bool: return t.x == 0):
		return "west"
	if all_on.call(func(t: Vector2i) -> bool: return t.x == CELL - 1):
		return "east"
	return ""
