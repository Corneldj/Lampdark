class_name StytheLair
extends SimSystem
## CRT-15 (stage CREATURES, after the creatures; Gameplay §7.4, §8.1, §8.3): the Stythe's lair.
##
## **The layout.** An unlit dead-end chamber complex: its tiles, and the row where the Stythe lays
## the bodies it takes, each place marked by a snuffed lamp among the men in-bye's remains. In a
## generated run it is the lair template's (GEN-16), read from the plan's lair site: every tile of
## the site's cells, and the row its first slot's places past the men laid out there (GEN-10 lays a
## line's things on its slot's tiles in order); a resumed run reads it the same. A fixed map's STYTHE
## entry may give it (`set_layout`); else it is every floor tile within stythe.lair_radius_tiles by
## path of the Stythe's lair tile, the row those tiles in row-major order (Proposed stand-in,
## CRT-15's notes).
##
## **Laying.** A drag reaching the lair lays the body (unconscious by then, RSC-03's 20 s run out)
## straight in the next free slot of the row, kept in the lair (BodyState.kept_in_lair). The Stythe
## keeps while at least one body it laid still lies on the lair's tiles (Proposed); none left, it
## goes from Keep to Lurk.
##
## **The lair's air.** Anyone on the lair's tiles, conscious or not, kept bodies included, gathers
## lair time each tick; at stythe.lair_soot_lung_s in all, counted across visits, they catch
## soot-lung (MinerOverlays.SOOT_LUNG; HAZ-06 gives it its cough). Only a cure resets the count.
##
## **Kept.** The laid list is the lair's record in GEN-13's diff log; lair time goes into
## snapshots (write_state). Never sent: the lair's place (except as seen tiles), the kept bodies,
## the counters. Server-only.

## {tick, victim, dragged_tiles, slot}: every arrival, for the Inquiry ("Dragged 130 tiles...").
var arrivals: Array[Dictionary] = []
## {tick, miner}: every soot-lung caught here.
var soot_lung: Array[Dictionary] = []
## miner entity -> ticks spent on the lair's tiles since its last cure.
var lair_ticks: Dictionary = {}
## The bodies laid, by row slot index: slot -> entity (0: free).
var slots: Dictionary = {}
var trail: BloodTrail = BloodTrail.new()
var stythe: StytheCreature = null
var _tiles: Dictionary = {}
var _row: Array[Vector2i] = []
## The lair tile the stand-in layout was derived from (re-derived if the lair moves); unset when a
## layout was given.
var _derived_from: Vector2i = Vector2i(2147483647, 0)
var _given: bool = false
## The lair template's cells (GEN-16), once the run's layouts were read; empty with no template.
var _cells: Dictionary = {}
var _template_read: bool = false
var _run: RunState = null


func stage() -> int:
	return StageTable.Stage.CREATURES


func order() -> int:
	return 30


func system_name() -> String:
	return "stythe_lair"


func bind(run: RunState) -> void:
	_run = run
	if run.miner_state != null:
		run.miner_state.overlay_changed.connect(func(entity: int, which: StringName, on: bool, _cause: String) -> void:
			if which == MinerOverlays.SOOT_LUNG and not on:
				lair_ticks.erase(entity))
	if run.diff_log != null:
		run.diff_log.register(DiffLog.Kind.LAIR, _replay)


## The run's Stythe: its trail, its home.
func attach(run: RunState, st: StytheCreature) -> void:
	stythe = st
	st.home = self
	trail.attach(run, st)


## GEN-10's lair (or a fixed map's): its tiles and its row of slots.
func set_layout(lair_tiles: Array[Vector2i], row_slots: Array[Vector2i]) -> void:
	_cells.clear()
	_tiles.clear()
	for t: Vector2i in lair_tiles:
		_tiles[t] = true
	_row = row_slots.duplicate()
	_given = true


## The lair's floor, row by row (a template's: of its loaded cells).
func tiles() -> Array[Vector2i]:
	_ensure_layout()
	var out: Array[Vector2i] = []
	if not _cells.is_empty():
		for raw: Variant in _cells.keys():
			var cell: Vector2i = raw
			if _run.mine == null or not _run.mine.native.is_loaded(cell):
				continue
			for y: int in WorldIds.CELL_TILES:
				for x: int in WorldIds.CELL_TILES:
					var t: Vector2i = cell * WorldIds.CELL_TILES + Vector2i(x, y)
					if _run.mine.native.is_walkable(t, true):
						out.append(t)
	else:
		for raw: Variant in _tiles.keys():
			out.append(raw)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return out


func row() -> Array[Vector2i]:
	_ensure_layout()
	return _row


func is_lair(tile: Vector2i) -> bool:
	_ensure_layout()
	if not _cells.is_empty():
		return _cells.has(WorldCoords.cell_of(tile))
	return _tiles.has(tile)


## The layout: a given one, the template's, or the stand-in (floor within stythe.lair_radius_tiles by
## path of the lair tile).
func _ensure_layout() -> void:
	if _given:
		return
	if not _template_read:
		_read_template()
	if not _cells.is_empty() or stythe == null or _run == null or _run.mine == null or stythe.lair == _derived_from:
		return
	_derived_from = stythe.lair
	_tiles.clear()
	_row.clear()
	var radius: int = Tuning.i(&"stythe.lair_radius_tiles")
	var dist: Dictionary = {stythe.lair: 0}
	var queue: Array[Vector2i] = [stythe.lair]
	var head: int = 0
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while head < queue.size():
		var t: Vector2i = queue[head]
		head += 1
		var d: int = int(Variants.number(dist[t]))
		if not _run.mine.native.is_walkable(t, false):
			continue
		_tiles[t] = true
		if d >= radius:
			continue
		for step: Vector2i in dirs:
			var n: Vector2i = t + step
			if not dist.has(n):
				dist[n] = d + 1
				queue.append(n)
	_row = tiles()


## GEN-16: the plan's lair site, when a template fits it: its cells, and the row its first slot's
## places past the men laid out on it. Read once the run's layouts are known (a fixed map has none).
func _read_template() -> void:
	if _run == null or _run.placed == null:
		return
	_template_read = true
	var layouts: LbLayouts = _run.placed.layouts
	if layouts == null:
		return
	for raw: Variant in Variants.array(layouts.plan_dict().get("sites", [])):
		var site: Dictionary = Variants.dict(raw)
		if str(site.get("kind", "")) != "lair":
			continue
		var door: Vector2i = site["door"]
		var poi: Dictionary = layouts.poi_at(door)
		var rects: Array = Variants.array(poi.get("slots", []))
		if str(poi.get("template", "")).is_empty() or rects.is_empty():
			return
		var region: Vector2i = poi["region"]
		var laid_out: int = 0
		for line: Variant in layouts.poi_contents(region, Variants.whole(poi["index"])):
			laid_out += 1 if Variants.whole(Variants.dict(line)["line"]) == 0 else 0
		var places: Rect2i = rects[0]
		_row.clear()
		var n: int = 0
		for y: int in range(places.position.y, places.end.y):
			for x: int in range(places.position.x, places.end.x):
				if n >= laid_out:
					_row.append(Vector2i(x, y))
				n += 1
		for c: Variant in Variants.array(poi.get("cells", [])):
			_cells[c] = true
		return


## The next free slot of the row (a slot whose body is gone is free again), or -1.
func next_slot() -> int:
	for i: int in row().size():
		if int(Variants.number(slots.get(i, 0))) == 0:
			return i
	return -1


## Lays `victim` (a body) straight in the next free slot, kept in the lair. Returns the slot.
func lay(run: RunState, st: StytheCreature, victim: int, dragged_tiles: int) -> int:
	var slot: int = next_slot()
	var at: Vector2i = row()[slot] if slot >= 0 else st.tile(run)
	if slot >= 0:
		slots[slot] = victim
	if run.movement != null:
		run.movement.place(run, victim, Vector2(at) + Vector2(0.5, 0.5))
	else:
		run.registry.move(victim, Vector2(at) + Vector2(0.5, 0.5))
	var b: BodyState = run.falls.body_of(victim) if run.falls != null else null
	if b != null:
		b.kept_in_lair = true
		# The drag is over (FallSystem would see it at stage FALLS, later this tick).
		b.dragged_by = 0
	arrivals.append({"tick": run.tick, "victim": victim, "dragged_tiles": dragged_tiles, "slot": slot})
	_record(run)
	return slot


## The bodies it laid that still lie on the lair's tiles (carried, risen or gone, they are not).
func kept_bodies(run: RunState) -> Array[int]:
	var out: Array[int] = []
	var ids: Array = slots.keys()
	ids.sort()
	for raw: Variant in ids:
		var e: int = int(Variants.number(slots[raw]))
		if e != 0 and _lies_here(run, e):
			out.append(e)
	return out


func _lies_here(run: RunState, entity: int) -> bool:
	if run.falls == null or not run.registry.has(entity):
		return false
	var b: BodyState = run.falls.body_of(entity)
	return b != null and b.carried_by == 0 and b.dragged_by == 0 and is_lair(run.registry.get_entity(entity).tile())


func tick(run: RunState) -> void:
	_run = run
	_keep(run)
	_air(run)


## A body no longer lying here is no longer kept; with none left, Keep gives way to Lurk.
func _keep(run: RunState) -> void:
	if stythe == null:
		return
	var changed: bool = false
	for raw: Variant in slots.keys():
		var e: int = int(Variants.number(slots[raw]))
		if e != 0 and not _lies_here(run, e):
			slots[raw] = 0
			var b: BodyState = run.falls.body_of(e) if run.falls != null else null
			if b != null:
				b.kept_in_lair = false
			changed = true
	var kept: Array[int] = kept_bodies(run)
	for e: int in stythe.kept.duplicate():
		if not kept.has(e):
			stythe.kept.erase(e)
	if changed:
		_record(run)
	if stythe.kept.is_empty() and stythe.state.name == &"keep":
		stythe.enter(run, &"lurk", "nobody kept")


## The lair's air: lair time for everyone on its tiles; soot-lung at stythe.lair_soot_lung_s.
func _air(run: RunState) -> void:
	if run.movement == null or run.miner_state == null:
		return
	var limit: int = roundi(Tuning.f(&"stythe.lair_soot_lung_s") * Tuning.f(&"net.tick_hz"))
	for slot: int in run.movement.miner_slots():
		var e: int = run.movement.miner(slot).entity_id
		var m: MinerStateSystem.Miner = run.miner_state.miner(e)
		if m == null or m.life == MinerTransitions.Life.DEAD or m.overlays.marks.has(MinerOverlays.SOOT_LUNG):
			continue
		if not is_lair(run.registry.get_entity(e).tile()):
			continue
		var t: int = int(Variants.number(lair_ticks.get(e, 0))) + 1
		lair_ticks[e] = t
		if t >= limit:
			run.miner_state.add_mark(e, MinerOverlays.SOOT_LUNG)
			soot_lung.append({"tick": run.tick, "miner": e})


## Lair time in seconds for `miner` since its last cure.
func lair_seconds(miner: int) -> float:
	return int(Variants.number(lair_ticks.get(miner, 0))) / Tuning.f(&"net.tick_hz")


## GEN-13: the row as laid, in the lair's cell.
func _record(run: RunState) -> void:
	if run.diff_log == null or stythe == null:
		return
	var laid: Array = []
	var ids: Array = slots.keys()
	ids.sort()
	for raw: Variant in ids:
		laid.append([int(Variants.number(raw)), int(Variants.number(slots[raw]))])
	run.diff_log.record(WorldCoords.cell_of(stythe.lair), DiffLog.Kind.LAIR, "lair", {"laid": laid})


func _replay(run: RunState, _cell: Vector2i, _key: String, p: Dictionary, _t: int) -> void:
	slots.clear()
	for raw: Variant in Variants.array(p.get("laid", [])):
		var pair: Array = raw
		var e: int = int(Variants.number(pair[1]))
		slots[int(Variants.number(pair[0]))] = e
		if stythe != null and e != 0 and not stythe.kept.has(e) and _lies_here(run, e):
			stythe.kept.append(e)


func write_state(writer: SimStateWriter) -> void:
	var ids: Array = lair_ticks.keys()
	ids.sort()
	writer.put_i64(ids.size())
	for raw: Variant in ids:
		writer.put_i64(int(Variants.number(raw)))
		writer.put_i64(int(Variants.number(lair_ticks[raw])))
	writer.put_i64(arrivals.size())


## NET-09: lair time per miner (the row is GEN-13's LAIR record), and a given layout.
func save_state() -> Dictionary:
	var out: Dictionary = {"lair_ticks": lair_ticks.duplicate()}
	if _given:
		out["tiles"] = tiles()
		out["row"] = _row.duplicate()
	return out


func load_state(_r: RunState, state: Dictionary) -> void:
	lair_ticks = Variants.dict(state.get("lair_ticks", {})).duplicate()
	if state.has("tiles"):
		var t: Array[Vector2i] = []
		t.assign(Variants.array(state["tiles"]))
		var r: Array[Vector2i] = []
		r.assign(Variants.array(state["row"]))
		set_layout(t, r)
