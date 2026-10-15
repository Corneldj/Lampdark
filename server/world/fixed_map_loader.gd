class_name FixedMapLoader
extends RefCounted
## GEN-03: a fixed, hand-made map from data/maps/<map>/ (the M1 grey box), loaded with no generator
## code. Its manifest names base camp's cell and blind side, the maze cells, a fixed run seed and
## the placements file (QA-01 edits it without code):
##   {format, name, run_seed, blind_side ("north"|"east"|"south"|"west"), base_camp [cx, cy], cells
##    [[cx, cy], ...], placements}
## load_cells() commits base camp (GEN-02, its blind side overridden) and exactly the listed cells,
## nothing else: lookups beyond them see rock. populate() then installs base camp's state (LFT-01,
## LFT-02: gates shut on a fresh run), hangs every timber hook (MNR-06), and places the coat heaps,
## creatures and items. Server-only: data/maps/ never ships to a client (check_pack_contents.sh).

const ROOT: String = "res://data/maps"
const SIDES: Array[String] = ["north", "east", "south", "west"]


## The map's manifest, or {} for a map without one (GEN-01's "test" map).
static func manifest(map_name: String) -> Dictionary:
	var path: String = "%s/%s/manifest.json" % [ROOT, map_name]
	if not FileAccess.file_exists(path):
		return {}
	return Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(path)))


static func run_seed(m: Dictionary) -> int:
	var parsed: Array = LaunchArgs.parse_u64(str(m.get("run_seed", "0")))
	return int(Variants.number(parsed[1]))


static func blind_side(m: Dictionary) -> int:
	return maxi(0, SIDES.find(str(m.get("blind_side", "north"))))


## Commits base camp and the manifest's cells at once (not through the stage-5 queue). Returns the
## number of cells committed, or -1 when a cell is missing or refused.
static func load_cells(mine: Mine, map_name: String) -> int:
	var m: Dictionary = manifest(map_name)
	var count: int = 0
	if m.has("base_camp"):
		var camp: Array = Variants.array(m["base_camp"])
		var data: LbCellData = Basecamp.cell_data(run_seed(m), blind_side(m))
		if data == null or Vector2i(int(Variants.number(camp[0])), int(Variants.number(camp[1]))) != Vector2i.ZERO \
				or not mine.native.commit(data):
			push_error("FixedMapLoader: base camp of %s did not load" % map_name)
			return -1
		count += 1
	for raw: Variant in Variants.array(m.get("cells", [])):
		var c: Array = raw
		var cell: Vector2i = Vector2i(int(Variants.number(c[0])), int(Variants.number(c[1])))
		var data: LbCellData = CellFile.load_file(CellFile.path_for(map_name, cell))
		if data == null or not mine.native.commit(data):
			push_error("FixedMapLoader: %s cell %s did not load" % [map_name, cell])
			return -1
		count += 1
	return count


## The placements as written (world tiles): {creatures, coat_heaps, items}.
static func placements(map_name: String) -> Dictionary:
	var m: Dictionary = manifest(map_name)
	var path: String = "%s/%s/%s" % [ROOT, map_name, str(m.get("placements", "placements.json"))]
	if not FileAccess.file_exists(path):
		return {}
	return Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(path)))


## Once the run's systems are installed on the loaded mine: base camp's state (when `base_camp`),
## the hooks, the coat heaps, the creatures and the items. Returns what it placed:
## {heaps: [entity ids], creatures: {kind: entity id}, items: [kind names], hooks: n}.
static func populate(run: RunState, map_name: String, base_camp: bool = true, fresh: bool = true) -> Dictionary:
	var m: Dictionary = manifest(map_name)
	var out: Dictionary = {"heaps": [], "creatures": {}, "items": [], "hooks": 0}
	if base_camp and m.has("base_camp") and run.base_camp == null:
		BaseCampState.attach(run, run_seed(m), blind_side(m), fresh)
	if run.mine != null and run.lamps != null:
		for raw: Variant in Variants.array(m.get("cells", [])):
			var c: Array = raw
			var cell: Vector2i = Vector2i(int(Variants.number(c[0])), int(Variants.number(c[1])))
			for a: Dictionary in run.mine.native.anchors(cell):
				if str(a.get("type", "")) == "timber_hook":
					run.lamps.hooks[WorldCoords.tile_of(cell, Vector2i(int(Variants.number(a["x"])), int(Variants.number(a["y"]))))] = true
					out["hooks"] = int(Variants.number(out["hooks"])) + 1
	var p: Dictionary = placements(map_name)
	for raw: Variant in Variants.array(p.get("coat_heaps", [])):
		var t: Array = raw
		var e: SimEntity = run.registry.create(WorldIds.EntityKind.COAT_HEAP, Vector2(float(Variants.number(t[0])), float(Variants.number(t[1]))) + Vector2(0.5, 0.5))
		Variants.array(out["heaps"]).append(e.id)
	for raw: Variant in Variants.array(p.get("creatures", [])):
		var d: Dictionary = raw
		var tile: Vector2i = _tile(d["tile"])
		var c: Creature = null
		match str(d.get("kind", "")):
			"MOTH":
				c = Moth.new()
			"TAPPER":
				c = Tapper.new()
			"STYTHE":
				c = StytheCreature.new()
		if c == null or run.creatures == null:
			continue
		if run.creatures.place_now(run, c, tile) == OK:
			Variants.dict(out["creatures"])[str(d["kind"])] = c.entity_id
	for raw: Variant in Variants.array(p.get("items", [])):
		var d: Dictionary = raw
		var at: Vector2 = Vector2(_tile(d["tile"])) + Vector2(0.5, 0.5)
		var kind_name: String = str(d.get("kind", ""))
		if not ItemKinds.Kind.has(kind_name) or run.inventory == null:
			push_error("FixedMapLoader: unknown item %s" % kind_name)
			continue
		var kind: ItemKinds.Kind = ItemKinds.Kind[kind_name]
		if kind == ItemKinds.Kind.GAUZE_LAMP and run.lamps != null:
			if run.lamps.create(run, float(Variants.number(d.get("oil", 0.5))), int(Variants.number(d.get("notches", 0))), false, 1, at) != null:
				Variants.array(out["items"]).append(kind_name)
			continue
		var state: Dictionary = {"fill": 1.0} if kind == ItemKinds.Kind.OIL_FLASK else {}
		var item: Item = run.inventory.world.make(kind, 1, state)
		if run.inventory.world.put(run, item, at) != 0:
			Variants.array(out["items"]).append(kind_name)
	return out


static func _tile(raw: Variant) -> Vector2i:
	var a: Array = raw
	return Vector2i(int(Variants.number(a[0])), int(Variants.number(a[1])))
