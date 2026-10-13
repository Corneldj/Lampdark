extends RefCounted
## Helpers for GEN-02: the road cells each gate leads into (a 3-wide road straight on, with a
## 1-wide branch 5 tiles past the cell edge), arched by the overlay or left raw.

const N: int = 20


## The cell a gate road enters, and its rows: rock with the road running on through it.
static func road_cell(gate: Dictionary) -> Array:
	var outward: Vector2i = gate["outward"]
	var tiles: Array = gate["tiles"]
	var first: Vector2i = tiles[0]
	# The gate stands 1-4 tiles inside base camp's cell: 5 tiles out is always the next cell.
	var cell: Vector2i = Vector2i(floori(float(first.x + outward.x * 5) / N), floori(float(first.y + outward.y * 5) / N))
	var grid: Array = []
	for y: int in N:
		var row: Array = []
		row.resize(N)
		row.fill("#")
		grid.append(row)
	for raw: Variant in tiles:
		var g: Vector2i = raw
		for k: int in N:
			var w: Vector2i = g + outward * (k + 1)
			var l: Vector2i = w - cell * N
			if l.x >= 0 and l.x < N and l.y >= 0 and l.y < N:
				grid[l.y][l.x] = "."
	# A branch off the road 5 tiles into this cell, at right angles, 6 tiles long.
	var side_step: Vector2i = Vector2i(outward.y, outward.x)
	var g0: Vector2i = tiles[0]
	var start: Vector2i = g0 + outward * 7
	for k: int in 7:
		var w: Vector2i = start - side_step * k
		var l: Vector2i = w - cell * N
		if l.x >= 0 and l.x < N and l.y >= 0 and l.y < N:
			grid[l.y][l.x] = "."
	var rows: PackedStringArray = PackedStringArray()
	for row: Array in grid:
		rows.append("".join(PackedStringArray(row)))
	return [cell, rows]


## A full cell file (one road zone) from rows, for loading beside base camp.
static func cell_file(cell: Vector2i, rows: PackedStringArray) -> Dictionary:
	var zones: Array = []
	for y: int in N:
		var z: Array = []
		for x: int in N:
			z.append(1 if rows[y][x] == "." else 0)
		zones.append(z)
	return {"format": 1, "cell": [cell.x, cell.y], "tiles": Array(rows), "zones": zones, "anchors": [], "barriers": [], "collapses": [],
		"road_graph": {"zones": [{"id": 1, "kind": "road"}], "portals": []}}
