extends SceneTree
## Writes data/maps/test/ (GEN-01's fixture map) through CellFile's canonical writer.
## Usage: godot --headless --path <game> -s tools/build/gen_test_map.gd
##
## Cell (0,0): a corridor (row 1) shut by air door 1 at (10, 1), a 25-tile detour through
## rows 1-5, collapse 3 that can block the detour at (9, 5), rails and sump mud on row 5,
## coal, brick and timber, gate 2 (open) into a chamber, and SND-01's zones and portals.
## Cell (1,0) carries the corridor on.


func _initialize() -> void:
	var rows_a: Array[String] = [
		"####################",
		"#.........D.........",
		"#.################.#",
		"#.################.#",
		"#.################.#",
		"#..===.....~~......#",
		"##########.#########",
		"#cccc####...########",
		"#cccc####...####TTTT",
		"#########...########",
		"BBBBBBBBB...BBBBBBBB",
		"#########...########",
		"####......s.......##",
		"####..............##",
		"####..............##",
		"####..............##",
		"####################",
		"####################",
		"####################",
		"####################",
	]
	var rows_b: Array[String] = []
	for y: int in 20:
		rows_b.append("...................." if y == 1 else "####################")
	_write("cell_0_0.json", Vector2i(0, 0), rows_a, true)
	_write("cell_1_0.json", Vector2i(1, 0), rows_b, false)
	quit()


## SND-01's zones for cell (0,0): 1 the west corridor and its column, 3 the east corridor
## and its column, 2 the detour road and the shaft down to the gate, 4 the chamber. Portals:
## 1 the air door (barrier 1), 4 and 5 openings at the detour's ends, 2 the gate (barrier 2).
static func zone_for(x: int, y: int, rows: Array[String], features: bool) -> int:
	var ch: String = rows[y][x]
	if not ch in [".", "=", "~", "s", "d"] or (features and ch in ["s", "d"]):
		return 0
	if not features:
		return 1
	if Vector2i(x, y) in [Vector2i(1, 5), Vector2i(18, 5)]:
		return 0  # opening portal tiles
	if y == 1:
		return 1 if x < 10 else 3
	if y >= 2 and y <= 4:
		return 1 if x == 1 else 3
	if y >= 5 and y <= 11:
		return 2
	return 4


func _write(file: String, coord: Vector2i, rows: Array[String], features: bool) -> void:
	var zones: Array = []
	for y: int in 20:
		var zone_row: Array = []
		for x: int in 20:
			zone_row.append(zone_for(x, y, rows, features))
		zones.append(zone_row)
	var dict: Dictionary = {"format": 1, "cell": [coord.x, coord.y], "tiles": rows, "zones": zones}
	if features:
		dict["anchors"] = [
			{"type": "timber_hook", "x": 4, "y": 1, "w": 1, "h": 1, "tags": ["road"], "kind": ""},
			{"type": "rubble_heap", "x": 8, "y": 5, "w": 1, "h": 1, "tags": [], "kind": ""},
			{"type": "landmark", "x": 14, "y": 5, "w": 1, "h": 1, "tags": [], "kind": ""},
			{"type": "chamber", "x": 4, "y": 12, "w": 14, "h": 4, "tags": ["high"], "kind": ""},
			{"type": "poi_slot", "x": 2, "y": 5, "w": 2, "h": 1, "tags": [], "kind": "lamp_cabin"},
			{"type": "rich_rock", "x": 1, "y": 7, "w": 4, "h": 2, "tags": [], "kind": ""},
		]
		dict["barriers"] = [{"id": 1, "portal": 1, "tiles": [30], "open": false}, {"id": 2, "portal": 2, "tiles": [250], "open": true}]
		dict["collapses"] = [{"id": 3, "standing": [[109, "."]], "fallen": [[109, "#"]], "is_fallen": false}]
		dict["road_graph"] = {
			"zones": [{"id": 1, "kind": "road"}, {"id": 2, "kind": "road"}, {"id": 3, "kind": "road"}, {"id": 4, "kind": "chamber"}],
			"portals": [
				{"id": 1, "kind": "air_door", "a": 1, "b": 3, "barrier": 1, "tiles": [30]},
				{"id": 2, "kind": "gate", "a": 2, "b": 4, "barrier": 2, "tiles": [250]},
				{"id": 4, "kind": "opening", "a": 1, "b": 2, "barrier": 0, "tiles": [101]},
				{"id": 5, "kind": "opening", "a": 2, "b": 3, "barrier": 0, "tiles": [118]},
			],
		}
	else:
		dict["road_graph"] = {"zones": [{"id": 1, "kind": "road"}], "portals": []}
	var data: LbCellData = CellFile.from_dict(dict, file)
	CellFile.save(data, "res://data/maps/test/" + file)
	print("gen_test_map: wrote %s (digest %s)" % [file, LbHash.to_hex(data.digest())])
