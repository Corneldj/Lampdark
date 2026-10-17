class_name TemplateDesignsV1
extends RefCounted
## GEN-16's v1 template set, drawn by code (tools/templates/v1/build.gd writes it as GEN-04 sources):
## biome cells for the pit bottom, the Seam and the Old Workings, a hub and a plain fallback for each,
## main roads, and the slice's points of interest.
##
## A biome cell is a ring road round the cell's middle that every stub's straight spoke meets, so
## any stub may fill or narrow and the floor stays one piece (GEN-04); what lies inside the ring
## gives each biome its look (Gameplay §12.2): the Seam open and pillared (pillars of rich rock,
## chambers 5-8 across, every one high: the Moth's roosts), the Old Workings close and timbered (2-wide roads,
## stalls and dead ends), the pit bottom railed. The stub sets come from tools/templates/v1/
## stub_sets.py: biome cells never turn as they are chosen, so the 3-wide biomes' sets are drawn as
## authored and transposed (no other turn keeps a 3-wide stub on a socket offset), the Old Workings'
## in all eight of their orientations; a set's weight halves with each stub, so a cell takes the
## template with the fewest blind headings that covers it most often.

const WIDE_SETS: Array[String] = [
	"N10 N15 E5 E15 S5 S10 W5", "N10 N15 E10 S15 W5 W10", "N10 N15 E10 S5 W15", "N5 E15 S5 W5", "N15 E15 S5 S15 W10",
	"N10 E10 S10 W5", "N15 E15 S5 W15", "N10 E15 S5 W10", "N5 E10 S5 W5", "N15 E10 S10 W5", "N10 E15 S15 W5", "N15 E5 S5 W5",
	"N15 E15 S10", "N15 W10", "N10 E5 S5 W5", "N15 E10 S5 W10", "N15 E15 S15 W5", "E10 S5", "N5 E15 S10 W5", "N10 E10 W10",
	"E15", "N5", "N15 E10 S15", "N15 E15 S10 W10", "N15 E5 S15 W10", "N10 E5"]
const NARROW_SETS: Array[String] = [
	"N10 N15 E5 E10 S5 W5", "N10 E10 S10 W5", "N5 E10 S5 W5", "N5 E15 S10 W5", "N5 E5", "N10 E5", "N5 E5 S5", "N10 S5",
	"N15 E15 S5", "N5 E10", "N15 E15 S10", "N10 E5 S10 W5", "N10 E10 S15 W5"]
const EVERY_STUB: String = "N5 N10 N15 E5 E10 E15 S5 S10 S15 W5 W10 W15"
const EDGE_OF: Dictionary = {"N": "north", "E": "east", "S": "south", "W": "west"}
const LANDMARKS: Array[String] = ["hand_pump", "brattice_sheet", "chalked_prop"]
const HUB_WEIGHT: float = 0.01
const BASE_CAMP_FILE: String = "res://data/maps/basecamp/cell_0_0.json"



## Every v1 template's spec, in a fixed order. `rules` is TemplateBuild.rules (the tuning's numbers).
static func all(rules: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for biome: String in ["pit_bottom", "seam", "old_workings"]:
		out.append_array(biome_cells(biome, rules))
		out.append(cell(biome + "_hub", "biome_cell", biome, EVERY_STUB, 0, rules).spec())
		out.append(cell(biome + "_plain", "fallback", biome, EVERY_STUB, 1, rules).spec())
	out.append_array(main_roads(rules))
	out.append_array(points_of_interest(rules))
	out.append(base_camp())
	return out


## GEN-02's base camp in the template format, unchanged: its fixed file's tiles and anchors (blind
## side north; Basecamp.rotate turns it), its three gate openings stubs at the edge. The run still
## builds base camp from the fixed file (Basecamp.cell_data); this keeps the two from drifting.
static func base_camp() -> Dictionary:
	var file: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(BASE_CAMP_FILE)))
	var anchors: Array = []
	for raw: Variant in Variants.array(file["anchors"]):
		var a: Dictionary = raw
		anchors.append([str(a["type"]), Variants.whole(a["x"]), Variants.whole(a["y"]), Variants.whole(a.get("w", 1)), Variants.whole(a.get("h", 1)),
			Variants.array(a.get("tags", [])), str(a.get("kind", ""))])
	var stubs: Array = []
	for edge: String in ["west", "east", "south"]:
		stubs.append({"cell": [0, 0], "edge": edge, "offset": 10, "max_width": 3, "depth": 0, "door": false})
	return {"id": "base_camp", "kind": "base_camp", "biome": "base_camp", "footprint": [1, 1], "weight": 1.0, "rows": Variants.array(file["tiles"]),
		"anchors": anchors, "stubs": stubs, "collapses": []}


## GEN-09's points of interest for the slice (and the deep workshop, which Standard and Full plans
## call for in ring 3): each kind with a door stub 2 wide at offset 10 (so it
## turns all eight ways), a poi_slot for each contents line in data/world/poi_kinds.json's order, a
## phone where its kind has one, and timber hooks. The two 2x1 kinds come twice, the door on a long
## side and on a short one; the lair is Old Workings with its door its only stub; the hoard is one
## high chamber.
## The contents lines whose thing is a carried load (the stretcher; the drum gear, the deep workshop's
## planned part): three tiles end to end (LoadSegment), laid in a room with floor all round, never in
## a niche, so it fits whichever way the template turns.
const LOAD_LINES: Dictionary = {"first_aid_station": [1], "deep_workshop": [1]}


static func points_of_interest(rules: Dictionary) -> Array[Dictionary]:
	var kinds: Dictionary = Variants.dict(Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(TemplateBuild.POI_KINDS))).get("kinds", {}))
	var out: Array[Dictionary] = []
	var galleries: Array = [["lamp_cabin", 0], ["fitters_shop", 1], ["stores", 2], ["fuel_store", 3], ["electricians_cabin", 4],
		["first_aid_station", 5], ["deep_workshop", 6]]
	for g: Array in galleries:
		var kind: String = str(g[0])
		var row: Dictionary = Variants.dict(kinds.get(kind, {}))
		var loads: Array = Variants.array(LOAD_LINES.get(kind, []))
		var poi: TemplateCanvas = gallery_poi(kind + "_01", kind, Variants.whole(row.get("contents_lines", 1)), Variants.flag(row.get("phone", false)),
			Variants.whole(g[1]), rules, loads)
		if kind == "deep_workshop":
			poi.biome = "old_workings" # ring 3's, the deep biomes folded into the Old Workings for v1
		out.append(poi.spec())
	out.append(hoard_poi(rules).spec())
	out.append(lair_poi(rules).spec())
	for side: String in ["long", "short"]:
		out.append(substation_poi(side, rules).spec())
		out.append(engine_house_poi(side, rules).spec())
	return out


## A biome's cells: each stub set's design in every orientation that keeps its stubs on the offsets.
static func biome_cells(biome: String, rules: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	var sets: Array[String] = NARROW_SETS if biome == "old_workings" else WIDE_SETS
	var prefix: String = {"pit_bottom": "pit_road", "seam": "seam_ring", "old_workings": "old_ring"}[biome]
	for i: int in sets.size():
		var base: Dictionary = cell("%s_%02d" % [prefix, i + 1], "biome_cell", biome, sets[i], i, rules).spec()
		var turns: Array = [[0, false], [3, true]] if biome != "old_workings" else \
			[[0, false], [1, false], [2, false], [3, false], [0, true], [1, true], [2, true], [3, true]]
		for t: Array in turns:
			var o: int = Variants.whole(t[0])
			var mirror: bool = Variants.flag(t[1])
			var suffix: String = "" if o == 0 and not mirror else ("_%s%d" % ["m" if mirror else "r", o])
			var turned: Variant = TemplateCanvas.oriented(base, o, mirror, str(base["id"]) + suffix)
			if turned == null:
				continue
			var spec: Dictionary = turned
			var key: String = _shape_key(spec)
			if seen.has(key):
				continue
			seen[key] = true
			out.append(spec)
	return out


## One biome cell (or its hub or fallback) for a stub set: the ring, its interior by `variant`, the
## spokes, the biome's dressing and every anchor GEN-16 asks of a cell template.
static func cell(id: String, kind: String, biome: String, stub_set: String, variant: int, rules: Dictionary) -> TemplateCanvas:
	var width: int = 2 if biome == "old_workings" else 3
	var lo: int = 3 if width == 3 else 4
	var hi: int = TemplateCanvas.CELL - 1 - lo
	var c: TemplateCanvas = TemplateCanvas.new(id, kind, biome)
	var stubs: Array[Array] = _parse(stub_set)
	c.weight = HUB_WEIGHT if kind == "biome_cell" and stubs.size() == 12 else pow(2.0, 4 - stubs.size())
	if kind == "fallback":
		c.weight = 1.0
	# The ring, `width` wide, from lo to hi: every spoke from offset 5, 10 or 15 meets it.
	c.rect(lo, lo, hi - lo + 1, width)
	c.rect(lo, hi - width + 1, hi - lo + 1, width)
	c.rect(lo, lo, width, hi - lo + 1)
	c.rect(hi - width + 1, lo, width, hi - lo + 1)
	var interior: String = _interior_of(biome, variant, kind)
	_interior(c, interior, biome, variant)
	for s: Array in stubs:
		c.spoke(str(s[0]), Variants.whole(s[1]), width, lo)
	_dress(c, biome, width, lo, hi, variant)
	_anchors(c, biome, width, lo, hi, variant, interior, stubs, rules)
	c.auto_hooks(Variants.whole(rules.get("hook_reach_tiles", 4)))
	return c


static func _parse(stub_set: String) -> Array[Array]:
	var out: Array[Array] = []
	for word: String in stub_set.split(" ", false):
		out.append([str(EDGE_OF[word.substr(0, 1)]), int(word.substr(1))])
	return out


## What fills the ring: the Seam's pillars, chambers and halls; the Old Workings' stalls; the pit
## bottom's pillars and cross roads. The fallback keeps a plain pillar (stalls in the Old Workings,
## whose ring corners all meet a spoke when every stub is there).
static func _interior_of(biome: String, variant: int, kind: String) -> String:
	if kind != "biome_cell" or variant < 0:
		return "stalls" if biome == "old_workings" else "pillar"
	match biome:
		"seam":
			return ["chamber_we", "pillar", "chamber_ns", "hall", "chamber_we", "cross_we", "chamber_ns", "pillar", "chamber_we", "cross_ns"][variant % 10]
		"old_workings":
			return ["stalls", "cross1", "stalls_low", "split", "stalls"][variant % 5]
	return ["pillar", "cross_we", "cross_ns", "pillar"][variant % 4]


static func _interior(c: TemplateCanvas, interior: String, biome: String, variant: int) -> void:
	match interior:
		"chamber_we":
			c.rect(7, 7, 6, 6)
			c.rect(6, 9, 1, 2)
			c.rect(13, 9, 1, 2)
			c.anchor("chamber", 7, 7, 6, 6, ["high"])
		"chamber_ns":
			c.rect(7, 7, 6, 6)
			c.rect(9, 6, 2, 1)
			c.rect(9, 13, 2, 1)
			c.anchor("chamber", 7, 7, 6, 6, ["high"])
		"hall":
			c.rect(9, 6, 2, 8)
			c.rect(6, 9, 8, 2)
		"cross_we":
			c.rect(6, 9, 8, 3)
		"cross_ns":
			c.rect(9, 6, 3, 8)
		"cross1":
			c.rect(9, 6, 1, 8)
			c.rect(6, 10, 8, 1)
		"split":
			c.rect(6, 9, 8, 2)
			for x: int in [8, 11]:
				c.rect(x, 6, 1, 2)
				c.rect(x, 12, 1, 2)
		"stalls":
			for x: int in [8, 11]:
				c.rect(x, 6, 1, 3)
			c.rect(6, 10, 3, 1)
		"stalls_low":
			for x: int in [8, 11]:
				c.rect(x, 11, 1, 3)
			c.rect(11, 9, 3, 1)


## The biome's dressing: the pit bottom's rails on every road's centre line and coal faces outside
## the ring; the Seam's coal on its pillars; the Old Workings' timbered ribs (a third at most).
static func _dress(c: TemplateCanvas, biome: String, width: int, lo: int, hi: int, variant: int) -> void:
	match biome:
		"pit_bottom":
			var mid_lo: int = lo + width / 2
			var mid_hi: int = hi - width / 2
			for t: int in range(lo, hi + 1):
				for p: Vector2i in [Vector2i(t, mid_lo), Vector2i(t, mid_hi), Vector2i(mid_lo, t), Vector2i(mid_hi, t)]:
					if c.at(p.x, p.y) == ".":
						c.put(p.x, p.y, "=")
			for raw: Variant in c.stubs:
				var s: Dictionary = raw
				for d: int in lo:
					var p: Vector2i = c.edge_tile(str(s["edge"]), Variants.whole(s["offset"]), d)
					c.put(p.x, p.y, "=")
			for p: Vector2i in c.faces():
				if p.x < lo or p.y < lo or p.x > hi or p.y > hi:
					if (p.x + p.y + variant) % 3 == 0:
						c.put(p.x, p.y, "c")
		"seam":
			for p: Vector2i in c.faces():
				if p.x > lo + width - 1 and p.y > lo + width - 1 and p.x < hi - width + 1 and p.y < hi - width + 1 and (p.x + 2 * p.y + variant) % 4 != 0:
					c.put(p.x, p.y, "c")
		"old_workings":
			var ribs: Array[Vector2i] = []
			for p: Vector2i in c.faces():
				if p.x < lo or p.y < lo or p.x > hi or p.y > hi:
					ribs.append(p)
			for i: int in ribs.size():
				if (i + variant) % 4 == 0:
					c.put(ribs[i].x, ribs[i].y, "T")


static func _anchors(c: TemplateCanvas, biome: String, width: int, lo: int, hi: int, variant: int, interior: String, stubs: Array[Array],
		rules: Dictionary) -> void:
	var band: int = lo + width - 1 # the ring's inner row on its north side
	# One landmark and one or two rubble heaps on the ring (GEN-04's rule).
	var landmark: Vector2i = c.free_floor([Vector2i(lo + 4 + variant % 5, band), Vector2i(hi - 2, lo + 4), Vector2i(lo + 6, hi - width + 1)])
	c.anchor("landmark", landmark.x, landmark.y, 1, 1, [], LANDMARKS[variant % LANDMARKS.size()])
	var heap: Vector2i = c.free_floor([Vector2i(hi - width + 1, hi - 3), Vector2i(lo, lo + 6), Vector2i(lo + 7, hi)])
	c.anchor("rubble_heap", heap.x, heap.y)
	if variant % 2 == 0:
		var second: Vector2i = c.free_floor([Vector2i(lo + 7, hi - width + 1), Vector2i(hi, lo + 7)])
		if second.x >= 0:
			c.anchor("rubble_heap", second.x, second.y)
	# Remains in the ring's corners, a stall's end or a chamber's corner.
	var placed: int = 0
	for p: Vector2i in c.corners():
		if placed >= 2:
			break
		if c.free_floor([p]) == p:
			c.anchor("remains", p.x, p.y)
			placed += 1
	# A wall fixture (a phone may hang there) on a face of the ring's inside, and items and trap sites
	# on its roads.
	for p: Vector2i in c.faces():
		if p.x > lo and p.y > lo and p.x < hi and p.y < hi:
			c.anchor("wall_fixture", p.x, p.y)
			break
	for p: Vector2i in [Vector2i(hi - 1, band), Vector2i(lo + 1, hi - 2)]:
		var t: Vector2i = c.free_floor([p, p + Vector2i(0, 1), p + Vector2i(1, 0)])
		if t.x >= 0:
			c.anchor("item", t.x, t.y)
	var traps: int = 2 if biome == "old_workings" else 1
	for i: int in traps:
		var t: Vector2i = c.free_floor([Vector2i(lo + 2 + 5 * i, hi - 1), Vector2i(hi - 1, lo + 3 + 5 * i), Vector2i(lo + 1, lo + 8 + i)])
		if t.x >= 0:
			c.anchor("trap_site", t.x, t.y)
	# Collapse alternates across the spokes, past their throats: one, and a second where there is
	# another spoke.
	var falls: int = 0
	for s: Array in stubs:
		if falls >= 2:
			break
		c.collapse_across(str(s[0]), Variants.whole(s[1]), width, TemplateCanvas.THROAT_DEPTH)
		falls += 1
	match biome:
		"seam":
			if interior == "pillar":
				c.anchor("rich_rock", 8, 8, 4, 4)
			c.anchor("gas_area", hi - width + 1, hi - width + 1, width, width)
			c.anchor("low_road", lo + 4, hi - width / 2, 5, 1)
		"pit_bottom":
			if interior == "pillar":
				c.anchor("rich_rock", 8, 8, 4, 4)
			c.anchor("low_road", lo + 4, hi - width / 2, 5, 1)
		"old_workings":
			for p: Vector2i in c.corners():
				if c.floor_neighbours(p.x, p.y) == 1 and p.x > lo and p.y > lo and p.x < hi and p.y < hi:
					var run: Rect2i = _dead_end_run(c, p)
					if run.size.x > 0:
						c.anchor("gas_dead_end", run.position.x, run.position.y, run.size.x, run.size.y, ["dead_end"])
						break
			c.anchor("low_road", lo + 4, hi, 4, 1)


## The straight run of road (3 tiles or more) a dead end at `p` closes, as a rectangle.
static func _dead_end_run(c: TemplateCanvas, p: Vector2i) -> Rect2i:
	for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if not c.walkable(p.x + step.x, p.y + step.y):
			continue
		var tiles: Array[Vector2i] = [p]
		var t: Vector2i = p + step
		while tiles.size() < 6 and c.walkable(t.x, t.y) and c.floor_neighbours(t.x, t.y) <= 2:
			tiles.append(t)
			t += step
		if tiles.size() >= 3:
			var a: Vector2i = tiles[0]
			var b: Vector2i = tiles[tiles.size() - 1]
			return Rect2i(mini(a.x, b.x), mini(a.y, b.y), absi(a.x - b.x) + 1, absi(a.y - b.y) + 1)
	return Rect2i()


## GEN-07's main roads (drawn east to west; the deriver transposes them for a north-south road): ten
## templates over the five shapes and the old fall, in pit-bottom, Seam and Old Workings dressing.
static func main_roads(rules: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var designs: Array = [["main_straight_01", "straight", false, "pit_bottom"], ["main_straight_02", "straight", false, "seam"],
		["main_straight_03", "straight", false, "old_workings"], ["main_bend_05", "bend_5", false, "pit_bottom"],
		["main_bend_10", "bend_10", false, "seam"], ["main_bend_15", "bend_15", false, "old_workings"],
		["main_crossing_01", "crossing", false, "pit_bottom"], ["main_crossing_02", "crossing", false, "seam"],
		["main_oldfall_01", "straight", true, "pit_bottom"], ["main_oldfall_02", "straight", true, "old_workings"]]
	for i: int in designs.size():
		var d: Array = designs[i]
		out.append(main_road(str(d[0]), str(d[1]), Variants.flag(d[2]), str(d[3]), i, rules).spec())
	return out


## One main road: a 3-wide road on rows 9-11, its rails on row 10; side passages north and south at
## 5, 10 and 15 (a bend's chicane at its offset, an old fall's rock between 5 and 10), or a
## north-south road for a crossing. Each side passage's mouth is a door site (GEN-10's air doors), a
## collapse alternate on one side passage, and the anchors every cell template carries.
static func main_road(id: String, shape: String, old_fall: bool, dressing: String, variant: int, rules: Dictionary) -> TemplateCanvas:
	var c: TemplateCanvas = TemplateCanvas.new(id, "main_road", "main_road")
	c.shape = shape
	c.old_fall = old_fall
	c.rect(0, 9, 20, 3)
	for x: int in 20:
		c.put(x, 10, "=")
	c.stubs.append({"cell": [0, 0], "edge": "west", "offset": 10, "max_width": 3, "depth": 0, "door": false})
	c.stubs.append({"cell": [0, 0], "edge": "east", "offset": 10, "max_width": 3, "depth": 0, "door": false})
	for d: int in TemplateCanvas.THROAT_DEPTH:
		for y: int in range(9, 12):
			c.throats[Vector2i(d, y)] = true
			c.throats[Vector2i(19 - d, y)] = true
	var passages: Array[Array] = [] # [edge, offset]
	if shape == "crossing":
		c.rect(9, 0, 3, 20)
		for y: int in 20:
			c.put(10, y, "=")
		for edge: String in ["north", "south"]:
			c.stubs.append({"cell": [0, 0], "edge": edge, "offset": 10, "max_width": 3, "depth": 0, "door": false})
			for a: int in range(9, 12):
				for d: int in TemplateCanvas.THROAT_DEPTH:
					var t: Vector2i = c.edge_tile(edge, a, d)
					c.throats[t] = true
	elif old_fall:
		# The fall chokes the road between its passages at 5 and 10, so each passage joins a half: its
		# exits (GEN-07: north at 5, south at 15) take the detour, and a planned site's door, which may
		# take an exit's edge at another offset, still finds a passage.
		c.rect(7, 9, 2, 3, "#")
		for o: int in [5, 10, 15]:
			c.spoke("north", o, 3, 9)
			c.spoke("south", o, 3, 8)
			passages.append(["north", o])
			passages.append(["south", o])
	else:
		for o: int in [5, 10, 15]:
			c.spoke("north", o, 3, 9)
			c.spoke("south", o, 3, 8)
			passages.append(["north", o])
			passages.append(["south", o])
		if shape.begins_with("bend_"):
			var b: int = int(shape.substr(5))
			c.put(b - 1, 9, "#")
			c.put(b - 1, 10, "#")
			c.put(b + 1, 10, "#")
			c.put(b + 1, 11, "#")
	# A niche off the road for the men's remains; the landmark and rubble on the road.
	var niche: Vector2i = Vector2i(2, 8) if shape != "crossing" else Vector2i(2, 12)
	c.put(niche.x, niche.y, ".")
	c.anchor("remains", niche.x, niche.y)
	var mark: Vector2i = c.free_floor([Vector2i(6 + variant % 3, 11), Vector2i(13, 9), Vector2i(3, 11)])
	c.anchor("landmark", mark.x, mark.y, 1, 1, [], LANDMARKS[variant % LANDMARKS.size()])
	var heap: Vector2i = c.free_floor([Vector2i(16, 11), Vector2i(12, 9), Vector2i(3, 9)])
	c.anchor("rubble_heap", heap.x, heap.y)
	# A trap site on the road, off its rails (HAZ-01: the men in-bye's jaws lie on the roads).
	var trap: Vector2i = c.free_floor([Vector2i(14, 11), Vector2i(5, 9), Vector2i(11, 11)])
	if trap.x >= 0:
		c.anchor("trap_site", trap.x, trap.y)
	# Each side passage's mouth a door site; a collapse across one passage past its throat.
	for pas: Array in passages:
		var edge: String = str(pas[0])
		var o: int = Variants.whole(pas[1])
		var mouth: int = 8 if edge == "north" else 12
		c.anchor("door_site", o - 1, mouth, 3, 1)
	if not passages.is_empty():
		var first: Array = passages[0]
		c.collapse_across(str(first[0]), Variants.whole(first[1]), 3, TemplateCanvas.THROAT_DEPTH + 1)
	elif shape == "crossing":
		c.collapse([Vector2i(9, 3), Vector2i(10, 3), Vector2i(11, 3)])
	# A wall fixture on a rib, items on the road.
	for p: Vector2i in c.faces():
		if p.y == 8 or p.y == 12:
			c.anchor("wall_fixture", p.x, p.y)
			break
	for p: Vector2i in [Vector2i(4, 11), Vector2i(15, 9)]:
		var t: Vector2i = c.free_floor([p, p + Vector2i(1, 0)])
		if t.x >= 0:
			c.anchor("item", t.x, t.y)
	_dress_main_road(c, dressing, variant)
	c.auto_hooks(Variants.whole(rules.get("hook_reach_tiles", 4)))
	return c


static func _dress_main_road(c: TemplateCanvas, dressing: String, variant: int) -> void:
	var ribs: Array[Vector2i] = c.faces()
	for i: int in ribs.size():
		var p: Vector2i = ribs[i]
		if c.anchored(p.x, p.y):
			continue
		match dressing:
			"pit_bottom", "seam":
				if (i + variant) % 3 == 0:
					c.put(p.x, p.y, "c")
			"old_workings":
				if (i + variant) % 5 == 0 and (p.y < 8 or p.y > 12):
					c.put(p.x, p.y, "T")


## A 1x1 point of interest: the door's passage north from the south edge into a room (a chamber
## anchor: GEN-09's rooms are chamber zones), a second room beyond it when its contents need the
## space, and alcoves in the rooms' walls for its slots.
static func gallery_poi(id: String, kind: String, slots: int, phone: bool, variant: int, rules: Dictionary, loads: Array = []) -> TemplateCanvas:
	var c: TemplateCanvas = TemplateCanvas.new(id, "poi", "seam")
	c.poi_kind = kind
	c.spoke("south", 10, 2, 7, Vector2i.ZERO, true)
	c.rect(6, 8, 8, 5)
	c.anchor("chamber", 6, 8, 8, 5)
	var second: bool = slots > 4 or variant % 2 == 1
	if second:
		c.rect(6, 2, 8, 5)
		c.anchor("chamber", 6, 2, 8, 5)
		c.rect(9, 7, 2, 1)
	# Alcoves, one tile each, in the rooms' side walls: the slots in their order.
	var alcoves: Array[Vector2i] = []
	if second:
		alcoves.append_array([Vector2i(5, 3), Vector2i(14, 3), Vector2i(5, 5), Vector2i(14, 5)])
	alcoves.append_array([Vector2i(5, 9), Vector2i(14, 9), Vector2i(5, 11), Vector2i(14, 11)])
	for i: int in mini(slots, alcoves.size()):
		var a: Vector2i = alcoves[i]
		if loads.has(i):
			# A load's slot: in the room on its alcove's row, two tiles off the wall (the order holds).
			c.anchor("poi_slot", 7 if a.x < 10 else 12, a.y)
			continue
		c.put(a.x, a.y, ".")
		c.anchor("poi_slot", a.x, a.y)
	if phone:
		_phone_on(c, 13)
	c.auto_hooks(Variants.whole(rules.get("hook_reach_tiles", 4)))
	return c


## A phone wall fixture on a face of row `y` (the room's south wall), off the door's passage.
static func _phone_on(c: TemplateCanvas, y: int) -> void:
	for f: Vector2i in c.faces():
		if f.y == y and (f.x < 8 or f.x > 11):
			c.anchor("wall_fixture", f.x, f.y, 1, 1, [], "phone")
			return


## The Moth's hoard: one high chamber hung with coats, their heap in its north-west corner, its lamps
## in a row along the north wall beside it.
static func hoard_poi(rules: Dictionary) -> TemplateCanvas:
	var c: TemplateCanvas = TemplateCanvas.new("hoard_01", "poi", "seam")
	c.poi_kind = "hoard"
	c.spoke("south", 10, 2, 6, Vector2i.ZERO, true)
	c.rect(6, 6, 8, 8)
	c.anchor("chamber", 6, 6, 8, 8, ["high"])
	c.anchor("poi_slot", 6, 6)
	c.anchor("poi_slot", 7, 6, 6, 1)
	for x: int in [7, 9, 11, 13]:
		c.anchor("timber_hook", x, 6)
	c.auto_hooks(Variants.whole(rules.get("hook_reach_tiles", 4)))
	return c


## The Stythe's lair (2x2, as GEN-08 plans it): Old Workings, unlit, its door its only stub (south
## of its south-west cell); a room in each cell joined by roads 2 wide, with stalls off them (dead
## ends), the deepest room holding the row: the men laid out, lamps snuffed in a row at their feet,
## their brass checks; the tools and the kits in the room before it.
static func lair_poi(rules: Dictionary) -> TemplateCanvas:
	var c: TemplateCanvas = TemplateCanvas.new("lair_01", "poi", "old_workings", Vector2i(2, 2))
	c.poi_kind = "lair"
	c.spoke("south", 10, 2, 8, Vector2i(0, 1), true)
	# The rooms: the entry (south-west), then east, then the two deep ones to the north.
	for room: Vector2i in [Vector2i(6, 26), Vector2i(26, 26), Vector2i(6, 6), Vector2i(26, 6)]:
		c.rect(room.x, room.y, 8, 6)
		c.anchor("chamber", room.x, room.y, 8, 6)
	c.rect(14, 28, 12, 2) # entry to east
	c.rect(29, 12, 2, 14) # east to north-east
	c.rect(14, 8, 12, 2) # north-east to north-west
	# Stalls off the roads: dead ends 2 wide.
	c.rect(19, 30, 2, 3)
	c.rect(31, 18, 3, 2)
	c.rect(19, 10, 2, 3)
	# The row, along the deepest room's north wall (north-west): the men laid out from its west end,
	# the places past them the Stythe's (StytheLair reads them); a snuffed lamp at the foot of each
	# place from the third on, the brass checks beside the lamps. The tools and the kits, the lure, lie
	# in the north-east room, the way in. (Slots in their lines' order: cell by cell, row by row.)
	c.anchor("poi_slot", 6, 6, 8, 1)
	c.anchor("poi_slot", 8, 7, 6, 1)
	c.anchor("poi_slot", 8, 8)
	c.anchor("poi_slot", 31, 10)
	c.anchor("poi_slot", 26, 11)
	c.auto_hooks(Variants.whole(rules.get("hook_reach_tiles", 4)))
	return c


## A 2x1 point of interest's door: on the south of its west cell (a long side) or its west edge (a
## short side), its passage into the west room.
static func _door_2x1(c: TemplateCanvas, side: String) -> void:
	if side == "long":
		c.spoke("south", 10, 2, 8, Vector2i.ZERO, true)
	else:
		c.spoke("west", 10, 2, 6, Vector2i.ZERO, true)


## The substation (2x1): a room in each cell joined across the cell edge; LFT-05's fuse board, trip
## lever and main switch in the east room, the trip and the switch a few tiles apart in its bay
## (the west room's slot first, so it holds the spare fuse), and its phone.
static func substation_poi(side: String, rules: Dictionary) -> TemplateCanvas:
	var c: TemplateCanvas = TemplateCanvas.new("substation_%s_01" % side, "poi", "seam", Vector2i(2, 1))
	c.poi_kind = "substation"
	_door_2x1(c, side)
	c.rect(6, 6, 8, 6)
	c.anchor("chamber", 6, 6, 8, 6)
	c.rect(14, 8, 12, 2)
	c.rect(26, 6, 8, 6)
	c.anchor("chamber", 26, 6, 8, 6)
	c.put(5, 7, ".")
	c.anchor("poi_slot", 5, 7)
	c.anchor("poi_slot", 27, 6, 1, 1, [], "substation.fuse_board")
	c.anchor("poi_slot", 28, 10, 1, 1, [], "substation.trip_lever")
	c.anchor("poi_slot", 32, 10, 1, 1, [], "substation.main_switch")
	_phone_on(c, 12)
	c.auto_hooks(Variants.whole(rules.get("hook_reach_tiles", 4)))
	return c


## The haulage engine house (2x1): a room in each cell joined by a railed road, the tub's slot on its
## rails, the hammer's in the west room and a planned part's in the east.
static func engine_house_poi(side: String, rules: Dictionary) -> TemplateCanvas:
	var c: TemplateCanvas = TemplateCanvas.new("haulage_engine_house_%s_01" % side, "poi", "pit_bottom", Vector2i(2, 1))
	c.poi_kind = "haulage_engine_house"
	_door_2x1(c, side)
	c.rect(6, 6, 8, 6)
	c.anchor("chamber", 6, 6, 8, 6)
	c.rect(14, 8, 12, 3)
	for x: int in range(14, 26):
		c.put(x, 9, "=")
	c.rect(26, 6, 8, 6)
	c.anchor("chamber", 26, 6, 8, 6)
	c.anchor("poi_slot", 7, 7)
	c.anchor("poi_slot", 20, 9)
	c.anchor("poi_slot", 32, 10)
	c.auto_hooks(Variants.whole(rules.get("hook_reach_tiles", 4)))
	return c


## What two specs share when drawn the same: their tiles and stubs (for dropping a turned copy that
## repeats another).
static func _shape_key(spec: Dictionary) -> String:
	var stubs: Array = []
	for raw: Variant in Variants.array(spec["stubs"]):
		var s: Dictionary = raw
		stubs.append("%s%d" % [s["edge"], s["offset"]])
	stubs.sort()
	return "|".join(PackedStringArray(Variants.array(spec["rows"]))) + "#" + ",".join(PackedStringArray(stubs))
