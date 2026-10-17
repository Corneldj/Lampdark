class_name CreatureStarts
extends RefCounted
## CRT-18 (Gameplay §7.1, §7.2, §7.3, §8.1, §10.10, §12.5): a generated run's creatures start at
## their homes, once, at run start, after GEN-10's homes pass and with GEN-11's start windows
## committed, each through CRT-01's spawner (a start tile any client sees or holds in its margin
## makes it wait; one of each, never a second):
## - the Moth asleep at the roost the seed drew (GEN-10's start roost; the hoard for -1): on a floor
##   tile of the roost's chamber against its wall where no coat heap lies, drawn from the
##   creatures.moth stream, one more heap among the coats; at the hoard, the floor tile nearest it;
## - the Tapper in Tapper-rich rock (GEN-10's masses, its rich_rock pointed at them) in rings
##   tapper.start_rings (a staged run 1: modes.staging_tapper_start_rings), Tapper.start_tile's draw
##   among the loaded cells; rock 4 or more tiles thick if no mass is loaded there (Proposed);
## - the Stythe at its lair (the plan's lair site): the floor tile nearest the site's middle, its lair
##   set there; StytheLair reads the lair template's layout (GEN-16), its stand-in round it with none.
## A creature turned off (creatures.enabled), and the Tapper under Quiet Seam, never spawn (the
## spawner refuses). A resumed run takes its creatures from its save (NET-09): server_main never
## calls this then, and a kind already present is left alone. Server-only.


## Every start: {moth: {tile, result}, tapper: {...}, stythe: {...}}, each start tile (null for
## none found) and the spawner's Error (ERR_ALREADY_EXISTS for one already present, untouched).
static func spawn(run: RunState, layouts: LbLayouts) -> Dictionary:
	var out: Dictionary = {}
	if run.creatures == null or run.mine == null:
		return out
	var homes: Dictionary = layouts.homes_dict()
	var plan: Dictionary = layouts.plan_dict()
	out["moth"] = _start(run, WorldIds.EntityKind.MOTH, moth_tile(run, homes), func() -> Creature: return Moth.new())
	var tapper: Tapper = Tapper.new()
	if run.placed != null:
		tapper.rich_rock = run.placed.is_rich_rock
	out["tapper"] = _start(run, WorldIds.EntityKind.TAPPER, tapper_tile(run, str(plan.get("staging", ""))), func() -> Creature: return tapper)
	var stythe: StytheCreature = StytheCreature.new()
	var lair: Variant = lair_tile(run, plan)
	if lair != null:
		stythe.lair = lair
	out["stythe"] = _start(run, WorldIds.EntityKind.STYTHE, lair, func() -> Creature: return stythe)
	return out


static func _start(run: RunState, kind: WorldIds.EntityKind, tile: Variant, make: Callable) -> Dictionary:
	if run.creatures.count_of(kind) > 0:
		return {"tile": null, "result": ERR_ALREADY_EXISTS}
	if tile == null:
		Log.warn("creature starts: no start tile for the %s" % str(WorldIds.EntityKind.find_key(kind)).to_lower())
		return {"tile": null, "result": ERR_DOES_NOT_EXIST}
	var at: Vector2i = tile
	var c: Creature = make.call()
	return {"tile": at, "result": run.creatures.spawn(run, c, at)}


## The Moth's start: its start roost's chamber, a wall tile no heap holds (the stream's draw), any of
## its floor if every one holds one; or the floor nearest the hoard. Null with neither.
static func moth_tile(run: RunState, homes: Dictionary) -> Variant:
	var roosts: Array = Variants.array(homes.get("roosts", []))
	var start: int = int(Variants.number(homes.get("start_roost", -1)))
	if start >= 0 and start < roosts.size():
		var r: Rect2i = roosts[start]
		var heaps: Dictionary = {}
		if run.placed != null:
			for cell: Vector2i in _cells_of(r):
				for p: Dictionary in run.placed.of_kind(cell, "coat_heap"):
					heaps[p["tile"]] = true
		var wall: Array[Vector2i] = []
		var floor: Array[Vector2i] = []
		for y: int in range(r.position.y, r.end.y):
			for x: int in range(r.position.x, r.end.x):
				var t: Vector2i = Vector2i(x, y)
				if not run.mine.native.is_walkable(t) or heaps.has(t):
					continue
				floor.append(t)
				for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if not run.mine.native.is_walkable(t + step):
						wall.append(t)
						break
		var options: Array[Vector2i] = wall if not wall.is_empty() else floor
		if not options.is_empty():
			var rng: LbRng = run.stream(HashDomain.CREATURES_MOTH, PackedInt64Array([1]))
			return options[rng.range(0, options.size() - 1)]
	if homes.get("hoard", null) != null:
		var hoard: Vector2i = homes["hoard"]
		return nearest_floor(run, hoard, 10)
	return null


## The Tapper's start: Tapper.start_tile in its rings over the loaded cells, GEN-10's masses first.
static func tapper_tile(run: RunState, staging: String) -> Variant:
	var rings: Vector2 = tapper_rings(staging)
	var rich: Callable = run.placed.is_rich_rock if run.placed != null else Callable()
	var tile: Variant = Tapper.start_tile(run, rings, rich)
	if tile == null and rich.is_valid():
		tile = Tapper.start_tile(run, rings)
	return tile


## tapper.start_rings, or a staged run 1's modes.staging_tapper_start_rings.
static func tapper_rings(staging: String) -> Vector2:
	if staging == "1":
		return Tuning.range_f(&"modes.staging_tapper_start_rings")
	return Tuning.range_f(&"tapper.start_rings")


## The Stythe's start: the floor tile nearest the middle of the plan's lair site, in its cells.
static func lair_tile(run: RunState, plan: Dictionary) -> Variant:
	for raw: Variant in Variants.array(plan.get("sites", [])):
		var site: Dictionary = Variants.dict(raw)
		if str(site.get("kind", "")) != "lair":
			continue
		var cells: Array[Vector2i] = []
		var middle: Vector2 = Vector2.ZERO
		for c: Variant in Variants.array(site.get("cells", [])):
			var cell: Vector2i = c
			cells.append(cell)
			middle += Vector2(cell * WorldIds.CELL_TILES) + Vector2(WorldIds.CELL_TILES, WorldIds.CELL_TILES) / 2.0
		if cells.is_empty():
			return null
		middle /= float(cells.size())
		var best: Variant = null
		var best_d: float = INF
		for cell: Vector2i in cells:
			for y: int in WorldIds.CELL_TILES:
				for x: int in WorldIds.CELL_TILES:
					var t: Vector2i = cell * WorldIds.CELL_TILES + Vector2i(x, y)
					var d: float = (Vector2(t) + Vector2(0.5, 0.5)).distance_squared_to(middle)
					if d < best_d and run.mine.native.is_walkable(t):
						best = t
						best_d = d
		return best
	return null


## The walkable tile nearest `tile` within `radius` (Chebyshev rings outward, row by row), or null.
static func nearest_floor(run: RunState, tile: Vector2i, radius: int) -> Variant:
	for r: int in radius + 1:
		for dy: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var t: Vector2i = tile + Vector2i(dx, dy)
				if run.mine.native.is_walkable(t):
					return t
	return null


static func _cells_of(r: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var a: Vector2i = WorldCoords.cell_of(r.position)
	var b: Vector2i = WorldCoords.cell_of(r.end - Vector2i.ONE)
	for y: int in range(a.y, b.y + 1):
		for x: int in range(a.x, b.x + 1):
			out.append(Vector2i(x, y))
	return out
