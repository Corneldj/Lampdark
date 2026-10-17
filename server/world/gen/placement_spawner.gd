class_name PlacementSpawner
extends RefCounted
## GEN-10 (Gameplay §12.5): what generation places, spawned as each cell commits and let go as it
## unloads (GEN-11's cell_loaded and cell_unloading), so eviction and return respawn it.
## - Items lie where placed with their state (found lamps unlit with their oil and notches, part-used
##   cans, the revolver loaded, boxes of rounds), each keyed by its placement ID so GEN-13 records
##   and replays it: a placement whose cell already has a record (taken, or lying elsewhere) is
##   never spawned again. Loads (the stretcher, the drum gear) go down through MNR-14's carry.
## - Pit phones and coat heaps are entities (PHONE, COAT_HEAP), made at each load; timber hooks
##   join MNR-06's hooks.
## - The rest is kept here for its owners: armed collapses (HAZ-03 arms them), gas (HAZ-04,
##   HAZ-05), man-traps and staple pits (HAZ-01, HAZ-02), Tapper-rich rock (CRT-08), landmarks and
##   the men in-bye's remains (props, with their items laid on them). Air doors and sump mud went
##   into the cell before commit (MineLayouts.dress).
## - The run-start homes (roosts, the start roost, the near-gate phones, the electric lamp's cell,
##   the canary region) are layouts.homes_dict().
## Server-only: no anchor or placement is sent; the entities reach clients only when seen (NET-04).

## cell -> its placements (LbLayouts.place's dictionaries), while it is loaded.
var by_cell: Dictionary = {}
## cell -> entities made at its load (phones, heaps), destroyed as it unloads.
var made: Dictionary = {}
## cell -> the timber hook tiles it added.
var hooks: Dictionary = {}
## LFT-12: each loaded phone's placement id -> its PHONE entity.
var phones: Dictionary = {}
## LbLayouts.homes_dict(): the Moth's roosts and start, the hoard, the near-gate phones, the
## electric lamp's cell and the canary region.
var homes: Dictionary = {}
## How many of each kind were spawned or kept ("item:gauze_lamp", "phone"...), for logs and tests.
var counts: Dictionary = {}
var layouts: LbLayouts = null
var _run: RunState = null


## Placement for a run's generated mine, bound before its first cell commits.
static func install(run: RunState, layouts_in: LbLayouts) -> PlacementSpawner:
	var s: PlacementSpawner = PlacementSpawner.new()
	s.bind(run, layouts_in)
	run.placed = s
	return s


func bind(run: RunState, layouts_in: LbLayouts) -> void:
	_run = run
	layouts = layouts_in
	homes = layouts.homes_dict()
	if run.mine == null:
		return
	run.mine.native.cell_loaded.connect(func(cell: Vector2i) -> void: _on_loaded(cell))
	run.mine.native.cell_unloading.connect(func(cell: Vector2i) -> void: _on_unloading(cell))
	for cell: Vector2i in run.mine.native.loaded_cells():
		_on_loaded(cell)


## GEN-11: the cells whose windows commit before the first tick beside base camp's: the Moth's start
## (its start roost, or the hoard) and the Stythe's lair, from the homes and the plan.
static func start_cells(layouts_in: LbLayouts) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var h: Dictionary = layouts_in.homes_dict()
	var roosts: Array = Variants.array(h.get("roosts", []))
	var start: int = int(Variants.number(h.get("start_roost", -1)))
	if start >= 0 and start < roosts.size():
		var r: Rect2i = roosts[start]
		out.append(WorldCoords.cell_of(r.position + r.size / 2))
	elif h.get("hoard", null) != null:
		var hoard: Vector2i = h["hoard"]
		out.append(WorldCoords.cell_of(hoard))
	for raw: Variant in Variants.array(layouts_in.plan_dict().get("sites", [])):
		var site: Dictionary = Variants.dict(raw)
		if str(site.get("kind", "")) == "lair":
			var door: Vector2i = site["door"]
			if not out.has(door):
				out.append(door)
	return out


## A loaded cell's placements of a kind ("firedamp", "man_trap", "landmark"...).
func of_kind(cell: Vector2i, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw: Variant in Variants.array(by_cell.get(cell, [])):
		var p: Dictionary = raw
		if str(p["kind"]) == kind:
			out.append(p)
	return out


## Whether a loaded placement of `kind` covers `tile` (gas, rich rock, mud...).
func covers(tile: Vector2i, kind: String) -> bool:
	for p: Dictionary in of_kind(WorldCoords.cell_of(tile), kind):
		var at: Vector2i = p["tile"]
		var size: Vector2i = p["size"]
		if Rect2i(at, size).has_point(tile):
			return true
	return false


func firedamp_at(tile: Vector2i) -> bool:
	return covers(tile, "firedamp")


func blackdamp_at(tile: Vector2i) -> bool:
	return covers(tile, "blackdamp")


## CRT-08: Tapper-rich rock (its masses, in loaded cells).
func is_rich_rock(tile: Vector2i) -> bool:
	return covers(tile, "rich_rock")


## The cell's landmark: {thing, variant, tile}, or {}.
func landmark_of(cell: Vector2i) -> Dictionary:
	var marks: Array[Dictionary] = of_kind(cell, "landmark")
	return marks[0] if not marks.is_empty() else {}


func _on_loaded(cell: Vector2i) -> void:
	var run: RunState = _run
	if cell == Vector2i.ZERO or by_cell.has(cell):
		return
	_hang_hooks(run, cell)
	var list: Array = layouts.place(cell)
	by_cell[cell] = list
	var mine_made: Array[int] = []
	for raw: Variant in list:
		var p: Dictionary = raw
		var kind: String = str(p["kind"])
		var tile: Vector2i = p["tile"]
		var at: Vector2 = Vector2(tile) + Vector2(0.5, 0.5)
		match kind:
			"item":
				if _spawn_item(run, cell, p, at) != 0:
					_count("item:%s" % str(p["thing"]))
				continue
			"phone":
				var phone: int = run.registry.create(WorldIds.EntityKind.PHONE, at).id
				mine_made.append(phone)
				phones[str(p["id"])] = phone
			"coat_heap":
				mine_made.append(run.registry.create(WorldIds.EntityKind.COAT_HEAP, at).id)
		_count(kind)
	made[cell] = mine_made


func _on_unloading(cell: Vector2i) -> void:
	for p: Dictionary in of_kind(cell, "phone"):
		phones.erase(str(p["id"]))
	for raw: Variant in Variants.array(made.get(cell, [])):
		var e: int = int(Variants.number(raw))
		if _run.registry.has(e):
			_run.registry.destroy(e)
	made.erase(cell)
	if _run.lamps != null:
		for raw: Variant in Variants.array(hooks.get(cell, [])):
			_run.lamps.hooks.erase(raw)
	hooks.erase(cell)
	by_cell.erase(cell)


## MNR-06's timber hooks: every timber_hook anchor of the cell.
func _hang_hooks(run: RunState, cell: Vector2i) -> void:
	if run.lamps == null:
		return
	var added: Array[Vector2i] = []
	for raw: Variant in run.mine.native.anchors(cell):
		var a: Dictionary = raw
		if str(a.get("type", "")) != "timber_hook":
			continue
		var t: Vector2i = WorldCoords.tile_of(cell, Vector2i(int(Variants.number(a["x"])), int(Variants.number(a["y"]))))
		if not run.lamps.hooks.has(t):
			run.lamps.hooks[t] = true
			added.append(t)
	hooks[cell] = added


## One placed item, unless GEN-13 already has it (its record replays it, or it was taken). Its
## entity, or 0.
func _spawn_item(run: RunState, cell: Vector2i, p: Dictionary, at: Vector2) -> int:
	if run.inventory == null:
		return 0
	var pid: String = str(p["id"])
	if run.diff_log != null and not run.diff_log.payload_of(cell, DiffLog.Kind.ITEM, pid).is_empty():
		return 0
	var thing: String = str(p["thing"])
	var key: String = thing.to_upper()
	if not ItemKinds.Kind.has(key):
		push_error("PlacementSpawner: no item kind %s (placement %s)" % [thing, pid])
		return 0
	var kind: ItemKinds.Kind = ItemKinds.Kind[key]
	var oil: float = int(Variants.number(p["oil_milli"])) / 1000.0
	var count: int = maxi(1, int(Variants.number(p["count"])))
	var world: ItemWorld = run.inventory.world
	var item: Item = null
	match kind:
		ItemKinds.Kind.STRETCHER, ItemKinds.Kind.DRUM_GEAR:
			return run.loads.place(run, kind, at, 0, pid) if run.loads != null else 0
		ItemKinds.Kind.GAUZE_LAMP:
			var notches: int = int(Variants.number(p["notches"]))
			item = world.make(kind, 1, {"oil": oil if oil >= 0.0 else 1.0, "notches": maxi(0, notches), "lit": false, "wick": 1,
				"shutter": false, "hung": false})
		ItemKinds.Kind.ELECTRIC_LAMP:
			item = ElectricLamps.make(run)
		ItemKinds.Kind.REVOLVER:
			item = Revolver.make(run, count)
		ItemKinds.Kind.PARAFFIN_CAN:
			# A part-used can (Dry Stores) keeps its share of lamp.can_fills; a full one no state.
			item = world.make(kind, 1, {"fills": Tuning.f(&"lamp.can_fills") * oil} if oil >= 0.0 else {})
		ItemKinds.Kind.OIL_FLASK:
			item = world.make(kind, 1, {"fill": oil if oil >= 0.0 else 1.0})
		_:
			item = world.make(kind, count)
	item.placement = pid
	var entity: int = world.put(run, item, at)
	if kind == ItemKinds.Kind.GAUZE_LAMP and run.lamps != null:
		run.lamps.reconcile(run)
	return entity


func _count(key: String) -> void:
	counts[key] = int(Variants.number(counts.get(key, 0))) + 1
