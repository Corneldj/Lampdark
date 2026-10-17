class_name CollapsePoints
extends SimSystem
## HAZ-03 (Gameplay §12.5, §8.2, §6.1, §6.9, §6.6, §12.6; GDD §15.8): collapse points, road roofs
## ready to fall. GEN-10 arms at most one alternate a cell (its placements of kind "collapse"); each
## armed point standing in a loaded cell has:
## - **a tell:** a COLLAPSE_POINT entity on its tiles, bowed props and dribbling stone that VIS-03
##   shows only at 0.30, as a small thing (Proposed). In the dark only its creak warns. Unarmed
##   alternates and fallen points show nothing.
## - **a trigger:** SND-02's collapse hook, armed on the tiles its fall lands on (its rubble). Any
##   event of noise.collapse_trigger_np within noise.collapse_trigger_path_tiles by path, or a
##   firedamp blast within hazards.collapse_blast_trigger_tiles in a straight line, starts its creak.
##   A Fan surge never stops it, and a trigger mid-creak changes nothing.
## - **the creak:** hazards.collapse_creak_s, with a collapse_creak (noise.collapse_creak_np,
##   Proposed) every hazards.collapse_creak_interval_s.
## - **the fall,** in one tick at this stage, before light, the Road Graph and visibility:
##   - The standing set swaps for the fallen. GEN-01's tiles_changed has VIS-02 relight, SND-01 swap
##     the zones, and VIS-03's sight lines and CRT-02's paths follow.
##   - Who it takes, by the distance from each body's centre to the nearest rubble tile at that tick
##     (no rewind: the creak is the warning). On the rubble: unconscious (RSC-01's ROOF_FALL) on the
##     nearer open tile, the lamp beside them. Within hazards.collapse_pin_edge_tiles: Caught under a
##     timber pin (TimberPins). Within hazards.collapse_hurt_edge_tiles: Hurt. Miners include Hired
##     Hands, and the unconscious are pinned too (Proposed).
##   - A carrier's load is set down first. Lamps, items, loads, bodies and walking creatures on the
##     rubble go to the nearer open tile, unharmed (Proposed for creatures), so nothing is buried.
##   - One roof_fall (noise.roof_fall_np), heard from both sides. Chalk (MNR-10) and blood (CRT-15)
##     on the rubble are erased; `fell` is LFT-12's to cut the lines through it; GEN-13 keeps the
##     FALL record.
## A point falls once a run: its replay puts the fallen set back quietly, with no noise, injury or
## erasure, and it is never armed again. The map table changes only when someone rubs out the road.
## Server-only: no armed or creaking state leaves it; the tell is an entity seen like any small thing.

enum State { STANDING = 0, CREAKING = 1 }

const KEY_PREFIX: String = "collapse:"
## How far to look for the nearer open tile (tiles).
const OPEN_RADIUS: int = 8


class Point:
	extends RefCounted
	var id: int = 0
	var cell: Vector2i = Vector2i.ZERO
	## The alternate's id in its cell.
	var collapse: int = 0
	## The fallen set's solid tiles: where the roof lands.
	var rubble: Array[Vector2i] = []
	var state: State = State.STANDING
	## The COLLAPSE_POINT entity.
	var tell: int = 0
	var fall_tick: int = -1
	var next_creak: int = -1
	## The noise event that started the creak.
	var triggered_by: int = 0


signal triggered(point_id: int, event_id: int)
## LFT-12: the roof fell on `tiles` of `cell`; every line through them is cut.
signal fell(point_id: int, cell: Vector2i, tiles: Array[Vector2i])

## point id -> Point: every armed point in a loaded cell, standing or creaking.
var points: Dictionary = {}
## What happened: {tick, point, what ("armed", "triggered", "fell", "fell unseen"), ...}.
var history: Array[Dictionary] = []
## Each fall's takes: {tick, point, felled, pinned, hurt, moved}.
var falls: Array[Dictionary] = []
## Cells loaded since the last tick: armed then, once GEN-10's placements and GEN-13's replay are in.
var _pending: Array[Vector2i] = []
## A resumed run's creaking points (point id -> {fall_tick, next_creak, event}), taken at arming.
var _saved: Dictionary = {}


func stage() -> int:
	return StageTable.Stage.WORLD


func order() -> int:
	return 60


func system_name() -> String:
	return "collapse_points"


## Hashed while any point is armed, so a run without one hashes as before.
func hashed() -> bool:
	return not points.is_empty()


## The hook's id for a cell's alternate (the trap id of the pins it drops).
static func point_id(cell: Vector2i, collapse: int) -> int:
	return ((cell.x & 0xFFFF) << 32) | ((cell.y & 0xFFFF) << 16) | (collapse & 0xFFFF)


func bind(run: RunState) -> void:
	if run.noise != null:
		run.noise.collapse.collapse_triggered.connect(func(pid: int, event_id: int) -> void: on_triggered(run, pid, event_id))
	if run.mine != null:
		run.mine.native.cell_loaded.connect(func(cell: Vector2i) -> void:
			if not _pending.has(cell):
				_pending.append(cell))
		run.mine.native.cell_unloading.connect(func(cell: Vector2i) -> void: _on_unloading(run, cell))
	if run.diff_log != null:
		run.diff_log.register(DiffLog.Kind.FALL, _replay, Callable(), Callable(), KEY_PREFIX)


## Arms a loaded cell's standing alternate (GEN-10's placements do it for a generated mine; tests
## and fixed maps call it). Returns its point id, or 0 when it cannot stand armed.
func arm_alternate(run: RunState, cell: Vector2i, collapse: int) -> int:
	if run.mine == null or not run.mine.native.is_loaded(cell):
		return 0
	var pid: int = point_id(cell, collapse)
	if points.has(pid):
		return pid
	var found: Dictionary = {}
	for raw: Variant in run.mine.native.collapses(cell):
		var d: Dictionary = raw
		if int(Variants.number(d["id"])) == collapse:
			found = d
	if found.is_empty() or Variants.flag(found["is_fallen"]):
		return 0
	var p: Point = Point.new()
	p.id = pid
	p.cell = cell
	p.collapse = collapse
	for raw: Variant in Variants.array(found["rubble"]):
		var t: Vector2i = raw
		p.rubble.append(t)
	if p.rubble.is_empty():
		return 0
	p.rubble.sort()
	p.tell = run.registry.create(WorldIds.EntityKind.COLLAPSE_POINT, _centre(p.rubble)).id
	if run.noise != null:
		run.noise.collapse.arm(pid, p.rubble[0], p.rubble)
	if _saved.has(pid):
		var s: Dictionary = _saved[pid]
		_saved.erase(pid)
		p.state = State.CREAKING
		p.fall_tick = int(Variants.number(s["fall_tick"]))
		p.next_creak = int(Variants.number(s["next_creak"]))
		p.triggered_by = int(Variants.number(s["event"]))
	points[pid] = p
	history.append({"tick": run.tick, "point": pid, "what": "armed"})
	return pid


## SND-02's hook heard it: a standing point starts its creak; a creaking one changes nothing.
func on_triggered(run: RunState, pid: int, event_id: int) -> void:
	var p: Point = points.get(pid, null)
	if p == null or p.state != State.STANDING:
		return
	p.state = State.CREAKING
	p.fall_tick = run.tick + roundi(Tuning.f(&"hazards.collapse_creak_s") * Tuning.f(&"net.tick_hz"))
	p.next_creak = run.tick + 1
	p.triggered_by = event_id
	history.append({"tick": run.tick, "point": pid, "what": "triggered", "event": event_id})
	triggered.emit(pid, event_id)


func tick(run: RunState) -> void:
	_arm_pending(run)
	var ids: Array = points.keys()
	ids.sort()
	var interval: int = maxi(1, roundi(Tuning.f(&"hazards.collapse_creak_interval_s") * Tuning.f(&"net.tick_hz")))
	for raw: Variant in ids:
		var p: Point = points[raw]
		if p.state != State.CREAKING:
			continue
		if run.tick >= p.fall_tick:
			fall(run, p)
		elif run.tick >= p.next_creak:
			p.next_creak += interval
			if run.noise != null:
				run.noise.emit(NoiseTypes.Type.COLLAPSE_CREAK, p.rubble[0], {"origins": p.rubble.slice(0, 1)})


func _arm_pending(run: RunState) -> void:
	if _pending.is_empty():
		return
	var cells: Array[Vector2i] = _pending.duplicate()
	_pending.clear()
	cells.sort()
	for cell: Vector2i in cells:
		if run.placed == null or run.mine == null or not run.mine.native.is_loaded(cell):
			continue
		for placed: Dictionary in run.placed.of_kind(cell, "collapse"):
			arm_alternate(run, cell, int(Variants.number(placed["collapse"])))


## The fall, all in this tick.
func fall(run: RunState, p: Point) -> void:
	var takes: Dictionary = _who_it_takes(run, p.rubble)
	var felled: Array[int] = takes["felled"]
	var pinned: Array[int] = takes["pinned"]
	var hurt: Array[int] = takes["hurt"]
	for m: int in felled:
		_set_down(run, m)
	for m: int in pinned:
		_set_down(run, m)
	run.mine.native.set_collapse(p.cell, p.collapse, true)
	var moved: int = 0
	for m: int in felled:
		moved += _to_open(run, m, p.rubble)
		if run.falls != null and run.miner_state != null and run.miner_state.life(m) < MinerTransitions.Life.UNCONSCIOUS:
			run.falls.fall_unconscious(run, m, FallCause.Cause.ROOF_FALL, {"trap_id": p.id})
	moved += _clear_rubble(run, p.rubble)
	moved += _clear_loads(run, p.rubble)
	for m: int in pinned:
		if run.holds != null:
			run.holds.catch(run, m, CaughtHold.Kind.TIMBER_PIN, p.id)
	for m: int in hurt:
		if run.miner_state != null:
			run.miner_state.make_hurt(m, "roof_fall")
	if run.noise != null:
		run.noise.emit(NoiseTypes.Type.ROOF_FALL, p.rubble[0], {"origins": p.rubble})
	if run.chalk != null:
		run.chalk.store.erase_chalk(run, p.rubble)
	if run.stythe_lair != null:
		run.stythe_lair.trail.erase(p.rubble)
	if run.vision != null:
		for t: Vector2i in p.rubble:
			run.vision.erase_trail(t)
	fell.emit(p.id, p.cell, p.rubble)
	if run.diff_log != null:
		run.diff_log.record(p.cell, DiffLog.Kind.FALL, KEY_PREFIX + str(p.collapse), {"fallen_at": run.tick, "cuts": []})
	_let_go(run, p)
	falls.append({"tick": run.tick, "point": p.id, "felled": felled, "pinned": pinned, "hurt": hurt, "moved": moved})
	history.append({"tick": run.tick, "point": p.id, "what": "fell"})
	Log.info("collapse point %d fell at %s: %d felled, %d pinned, %d hurt" % [p.id, p.rubble[0], felled.size(), pinned.size(), hurt.size()])


## Every miner by the distance from its centre to the nearest rubble tile: {felled, pinned, hurt}.
func _who_it_takes(run: RunState, rubble: Array[Vector2i]) -> Dictionary:
	var felled: Array[int] = []
	var pinned: Array[int] = []
	var hurt: Array[int] = []
	var pin_edge: float = Tuning.f(&"hazards.collapse_pin_edge_tiles")
	var hurt_edge: float = Tuning.f(&"hazards.collapse_hurt_edge_tiles")
	for id: int in run.registry.ids():
		var e: SimEntity = run.registry.get_entity(id)
		if e.kind != WorldIds.EntityKind.MINER:
			continue
		var life: int = run.miner_state.life(id) if run.miner_state != null and run.miner_state.miner(id) != null else MinerTransitions.Life.UPRIGHT
		var d: float = distance_to(e.position, rubble)
		if d <= 0.0:
			felled.append(id)
		elif life == MinerTransitions.Life.DEAD:
			continue
		elif d <= pin_edge:
			pinned.append(id)
		elif d <= hurt_edge and life < MinerTransitions.Life.UNCONSCIOUS:
			hurt.append(id)
	return {"felled": felled, "pinned": pinned, "hurt": hurt}


## From a point to the nearest of the tiles (0 inside one).
static func distance_to(at: Vector2, tiles: Array[Vector2i]) -> float:
	var best: float = INF
	for t: Vector2i in tiles:
		var dx: float = maxf(maxf(t.x - at.x, 0.0), at.x - (t.x + 1))
		var dy: float = maxf(maxf(t.y - at.y, 0.0), at.y - (t.y + 1))
		best = minf(best, sqrt(dx * dx + dy * dy))
	return best


## A carrier puts down what they carry before the roof takes them (MNR-13).
func _set_down(run: RunState, miner: int) -> void:
	if run.carry != null and run.carry.is_carrying(miner):
		run.carry.set_down(run, miner, FiremanCarry.FELLED)
	if run.loads != null and run.loads.carrying(miner):
		run.loads.set_down(run, miner, LoadCarry.FELLED)


## A miner on the rubble to the nearer open tile. Returns 1 if moved.
func _to_open(run: RunState, miner: int, rubble: Array[Vector2i]) -> int:
	var at: Vector2 = _open_beside(run, run.registry.get_entity(miner).position, rubble)
	if at.x < -1e8:
		return 0
	run.movement.place(run, miner, at)
	return 1


## Lamps, items, loads, bodies and walking creatures left on the rubble, to the nearer open tile.
func _clear_rubble(run: RunState, rubble: Array[Vector2i]) -> int:
	var moved: int = 0
	var ids: Array[int] = []
	for id: int in run.registry.ids():
		ids.append(id)
	ids.sort()
	for id: int in ids:
		var e: SimEntity = run.registry.get_entity(id)
		if e == null or not rubble.has(e.tile()):
			continue
		match e.kind:
			WorldIds.EntityKind.ITEM:
				var it: Item = run.inventory.world.item_at(id) if run.inventory != null else null
				if it != null and ItemKinds.is_load(it.kind):
					continue  # _clear_loads: a pose its segment fits
				var at: Vector2 = _open_beside(run, e.position, rubble)
				if at.x > -1e8:
					run.registry.move(id, at)
					if run.inventory != null:
						run.inventory.world.moved(run, id)
					moved += 1
			WorldIds.EntityKind.MINER:
				moved += _to_open(run, id, rubble)
			_:
				if run.creatures != null:
					for c: Creature in run.creatures.creatures:
						if c.entity_id == id and not c is Tapper:
							var at: Vector2 = _open_beside(run, e.position, rubble)
							if at.x > -1e8:
								run.creatures.relocate(run, c, at)
								moved += 1
	return moved


## Loads (the stretcher, the drum gear) the fallen rock now cuts through, wherever their centre
## lies: to the nearest pose LoadSegment fits on open floor, their heading kept or turned square.
func _clear_loads(run: RunState, rubble: Array[Vector2i]) -> int:
	if run.inventory == null:
		return 0
	var solid: Callable = func(t: Vector2i) -> bool: return run.mine.native.is_solid(t)
	var near: Rect2i = _bounds(rubble).grow(3)
	var moved: int = 0
	var ids: Array = run.inventory.world.items.keys()
	ids.sort()
	for raw: Variant in ids:
		var e: int = int(Variants.number(raw))
		var it: Item = run.inventory.world.items[raw]
		if not ItemKinds.is_load(it.kind) or not run.registry.has(e):
			continue
		var at: Vector2 = run.registry.get_entity(e).position
		if not near.has_point(Vector2i(floori(at.x), floori(at.y))):
			continue
		var heading: int = int(Variants.number(it.state.get("heading", 0)))
		var seg: LoadSegment = LoadSegment.make(it.kind, at, heading)
		if not seg.collides(at.x, at.y, heading, solid):
			continue
		var pose: Dictionary = _load_pose(seg, at, heading, solid)
		if pose.is_empty():
			continue
		var to: Vector2 = pose["at"]
		run.registry.move(e, to)
		it.state["heading"] = int(Variants.number(pose["heading"]))
		run.inventory.world.moved(run, e)
		moved += 1
	return moved


## The nearest tile centre (ring by ring, in order) where the segment fits, its heading or square to it.
static func _load_pose(seg: LoadSegment, at: Vector2, heading: int, solid: Callable) -> Dictionary:
	var home: Vector2i = Vector2i(floori(at.x), floori(at.y))
	for r: int in OPEN_RADIUS + 1:
		for dy: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c: Vector2 = Vector2(home + Vector2i(dx, dy)) + Vector2(0.5, 0.5)
				for h: int in [heading & 0xFFFF, (heading + 16384) & 0xFFFF]:
					if not Variants.flag(solid.call(Vector2i(floori(c.x), floori(c.y)))) and not seg.collides(c.x, c.y, h, solid):
						return {"at": c, "heading": h}
	return {}


static func _bounds(tiles: Array[Vector2i]) -> Rect2i:
	var r: Rect2i = Rect2i(tiles[0], Vector2i.ONE)
	for t: Vector2i in tiles:
		r = r.expand(t).expand(t + Vector2i.ONE)
	return r


## The centre of the open tile nearest `at`, the rubble left out; (-INF, -INF) when there is none.
func _open_beside(run: RunState, at: Vector2, rubble: Array[Vector2i]) -> Vector2:
	var r: Dictionary = run.mine.native.nearest_open_tile(at, rubble, OPEN_RADIUS)
	if not Variants.flag(r.get("found", false)):
		return Vector2(-INF, -INF)
	var t: Vector2i = r["tile"]
	return Vector2(t) + Vector2(0.5, 0.5)


static func _centre(tiles: Array[Vector2i]) -> Vector2:
	var sum: Vector2 = Vector2.ZERO
	for t: Vector2i in tiles:
		sum += Vector2(t) + Vector2(0.5, 0.5)
	return sum / float(tiles.size())


## The point leaves: its tell gone, the hook disarmed.
func _let_go(run: RunState, p: Point) -> void:
	if run.registry.has(p.tell):
		run.registry.destroy(p.tell)
	if run.noise != null:
		run.noise.collapse.disarm(p.id)
	points.erase(p.id)


## A cell going: its standing points are let go (armed again when it comes back); a creaking one
## falls unseen, nobody near (its record keeps it fallen).
func _on_unloading(run: RunState, cell: Vector2i) -> void:
	_pending.erase(cell)
	var ids: Array = points.keys()
	ids.sort()
	for raw: Variant in ids:
		var p: Point = points[raw]
		if p.cell != cell:
			continue
		if p.state == State.CREAKING and run.diff_log != null:
			run.diff_log.record(p.cell, DiffLog.Kind.FALL, KEY_PREFIX + str(p.collapse), {"fallen_at": run.tick, "cuts": []})
			history.append({"tick": run.tick, "point": p.id, "what": "fell unseen"})
		_let_go(run, p)


## GEN-13: a fallen point comes back fallen, quietly (no noise, injury or erasure), never armed.
func _replay(run: RunState, cell: Vector2i, key: String, _payload: Dictionary, _tick: int) -> void:
	var collapse: int = key.substr(KEY_PREFIX.length()).to_int()
	run.mine.native.set_collapse(cell, collapse, true)
	var p: Point = points.get(point_id(cell, collapse), null)
	if p != null:
		_let_go(run, p)


func write_state(writer: SimStateWriter) -> void:
	var ids: Array = points.keys()
	ids.sort()
	writer.put_i64(ids.size())
	for raw: Variant in ids:
		var p: Point = points[raw]
		writer.put_i64(p.id)
		writer.put_i32(p.state)
		writer.put_i64(p.fall_tick)
		writer.put_i64(p.next_creak)
		writer.put_i64(p.tell)


## A creaking point keeps its timers through a save; standing ones are armed again as their cells load.
func save_state() -> Dictionary:
	var creaking: Dictionary = {}
	for raw: Variant in points.keys():
		var p: Point = points[raw]
		if p.state == State.CREAKING:
			creaking[p.id] = {"fall_tick": p.fall_tick, "next_creak": p.next_creak, "event": p.triggered_by}
	for raw: Variant in _saved.keys():
		creaking[raw] = _saved[raw]
	return {"creaking": creaking}


func load_state(_run: RunState, state: Dictionary) -> void:
	_saved = Variants.dict(state.get("creaking", {})).duplicate(true)
