extends GutTest
## GEN-03: the validation fails when any single feature is removed from a copy of the maze. Each
## case builds the grey box from its author (tools/build/m1_greybox_author.gd), takes one feature
## out, loads the copy into a fresh mine and expects that requirement's failure.

const Author = preload("res://tools/build/m1_greybox_author.gd")
const MAP: String = "m1_greybox"


func before_all() -> void:
	assert_true(Tuning.load_server())


func after_each() -> void:
	WorldCoords.ring_override = -1


## Sets a world tile's character in the built cells. New floor takes a neighbouring floor's zone,
## so SND-01 still stitches the copy.
static func _put(cells: Dictionary, tile: Vector2i, ch: String) -> void:
	var cell: Vector2i = WorldCoords.cell_of(tile)
	var local: Vector2i = WorldCoords.local_of(tile)
	var d: Dictionary = cells[cell]
	var rows: Array = d["tiles"]
	var row: String = rows[local.y]
	row[local.x] = ch
	rows[local.y] = row
	if ch == "." or ch == "=":
		var zones: Array = d["zones"]
		for n: Vector2i in [local + Vector2i(1, 0), local + Vector2i(-1, 0), local + Vector2i(0, 1), local + Vector2i(0, -1)]:
			if n.x >= 0 and n.x < 20 and n.y >= 0 and n.y < 20:
				var z: int = int(Variants.number(Variants.array(zones[n.y])[n.x]))
				var c: String = str(rows[n.y])[n.x]
				if z != 0 and (c == "." or c == "="):
					Variants.array(zones[local.y])[local.x] = z
					break


static func _fill(cells: Dictionary, from: Vector2i, to: Vector2i, ch: String) -> void:
	for y: int in range(from.y, to.y + 1):
		for x: int in range(from.x, to.x + 1):
			_put(cells, Vector2i(x, y), ch)


## The validation's failures for the maze after `mutate(cells, placements)`.
func _errors(mutate: Callable) -> Array[String]:
	var built: Dictionary = Author.build()
	var cells: Dictionary = built["cells"]
	var placements: Dictionary = Variants.dict(built["placements"]).duplicate(true)
	mutate.call(cells, placements)
	var mine: Mine = Mine.new()
	var m: Dictionary = FixedMapLoader.manifest(MAP)
	assert_true(mine.native.commit(Basecamp.cell_data(FixedMapLoader.run_seed(m), FixedMapLoader.blind_side(m))))
	for raw: Variant in cells.keys():
		var dict: Dictionary = cells[raw]
		var data: LbCellData = CellFile.from_dict(dict, "copy")
		assert_not_null(data, "the copy of %s loads" % raw)
		if data != null:
			mine.native.commit(data)
	var graph: RoadGraphService = RoadGraphService.new(mine, FixedMapLoader.run_seed(m))
	return M1GreyboxCheck.check(mine, MAP, placements, graph.graph)


func _expect(requirement: String, mutate: Callable) -> void:
	var errors: Array[String] = _errors(mutate)
	var hit: bool = false
	for e: String in errors:
		hit = hit or e.begins_with(requirement + ":")
	if not hit:
		gut.p("%s: %s" % [requirement, errors])
	assert_true(hit, "without its feature, '%s' fails" % requirement)


func test_the_copy_itself_passes() -> void:
	var errors: Array[String] = _errors(func(_c: Dictionary, _p: Dictionary) -> void: pass)
	for e: String in errors:
		gut.p(e)
	assert_eq(errors.size(), 0, "the unaltered copy passes (the shipped files are this author's output)")


func test_a_gate_road_without_its_rail_or_arch() -> void:
	_expect("gate_roads", func(c: Dictionary, _p: Dictionary) -> void: _put(c, Vector2i(10, -5), "."))
	_expect("gate_roads", func(c: Dictionary, _p: Dictionary) -> void: _put(c, Vector2i(8, -3), "#"))  # an arch brick back to rock


func test_a_chamber_four_across() -> void:
	_expect("widths", func(c: Dictionary, _p: Dictionary) -> void:
		var d: Dictionary = c[Vector2i(1, -1)]
		for a: Variant in Variants.array(d["anchors"]):
			var anchor: Dictionary = a
			if str(anchor["type"]) == "chamber":
				anchor["w"] = 4)


func test_no_loop() -> void:
	_expect("connectivity", func(c: Dictionary, _p: Dictionary) -> void: _fill(c, Vector2i(36, -5), Vector2i(38, -5), "#"))


func test_no_sight_line() -> void:
	_expect("sight_line", func(c: Dictionary, _p: Dictionary) -> void:
		_fill(c, Vector2i(22, -17), Vector2i(22, -15), "#")
		_fill(c, Vector2i(36, 5), Vector2i(38, 5), "#"))


func test_nothing_deep() -> void:
	_expect("depth", func(c: Dictionary, _p: Dictionary) -> void:
		_put(c, Vector2i(1, 27), "#")  # the south's deep branch cut off at its start
		_fill(c, Vector2i(27, -9), Vector2i(27, -8), "#"))  # and the 5x5's road


func test_too_few_coat_heaps() -> void:
	_expect("coat_heaps", func(_c: Dictionary, p: Dictionary) -> void:
		var heaps: Array = p["coat_heaps"]
		p["coat_heaps"] = heaps.slice(0, 5))


func test_a_road_beyond_the_tappers_reach() -> void:
	_expect("rock_faces", func(c: Dictionary, _p: Dictionary) -> void: _fill(c, Vector2i(28, -7), Vector2i(35, -6), "."))


func test_the_five_by_five_entered_in_line() -> void:
	_expect("centre_lines", func(c: Dictionary, _p: Dictionary) -> void: _put(c, Vector2i(26, -8), "."))


func test_no_rich_rock() -> void:
	_expect("rich_rock", func(c: Dictionary, _p: Dictionary) -> void:
		for raw: Variant in c.keys():  # every rock and coal tile becomes timber: no rich mass anywhere
			var d: Dictionary = c[raw]
			var rows: Array = d["tiles"]
			for y: int in rows.size():
				rows[y] = str(rows[y]).replace("#", "T").replace("c", "T"))


func test_no_thin_rock_pair() -> void:
	_expect("voice_pairs", func(c: Dictionary, _p: Dictionary) -> void:
		var d: Dictionary = c[Vector2i(1, 0)]
		d["anchors"] = Variants.array(d["anchors"]).filter(func(a: Dictionary) -> bool: return str(a["kind"]) != "m1.voice_thin"))


func test_no_air_door() -> void:
	_expect("air_door", func(c: Dictionary, _p: Dictionary) -> void:
		var d: Dictionary = c[Vector2i(1, 0)]
		_put(c, Vector2i(25, 12), "#")
		d["barriers"] = []
		var graph: Dictionary = d["road_graph"]
		graph["portals"] = Variants.array(graph["portals"]).filter(func(p: Dictionary) -> bool: return str(p["kind"]) != "air_door"))


func test_no_hooks() -> void:
	_expect("hooks_rubble", func(c: Dictionary, _p: Dictionary) -> void:
		var d: Dictionary = c[Vector2i(1, 0)]
		d["anchors"] = Variants.array(d["anchors"]).filter(func(a: Dictionary) -> bool: return str(a["type"]) != "timber_hook"))


func test_a_repeated_landmark() -> void:
	_expect("landmarks", func(c: Dictionary, _p: Dictionary) -> void:
		var d: Dictionary = c[Vector2i(0, 1)]
		for a: Variant in Variants.array(d["anchors"]):
			var anchor: Dictionary = a
			if str(anchor["type"]) == "landmark":
				anchor["kind"] = "hand_pump")


func test_a_deeper_ring() -> void:
	WorldCoords.ring_override = 1
	_expect("ring", func(_c: Dictionary, _p: Dictionary) -> void: pass)


func test_something_else() -> void:
	_expect("nothing_else", func(c: Dictionary, _p: Dictionary) -> void:
		var d: Dictionary = c[Vector2i(0, 1)]
		Variants.array(d["anchors"]).append({"type": "trap_site", "x": 1, "y": 9, "w": 1, "h": 1, "tags": [], "kind": ""}))
