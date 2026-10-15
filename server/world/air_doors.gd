class_name AirDoorSystem
extends SimSystem
## GEN-15 (Gameplay §6.1, §7.2, §7.4, §13.9, §12.6): the wooden air doors on GEN-01's barriers, in any
## loaded cell (a barrier whose tiles are WOODEN_DOOR). Shut is real shelter: GEN-01's barrier makes
## its tiles solid and opaque, so VIS-02's light, VIS-03's sight, SND-01's portal (a closed air door
## costs 12 np and cuts voice) and CRT-02's navigation all follow in the same tick
## (`tiles_changed`). A miner works a door by holding interact on it within touch range for
## mine.air_door_operate_s, silently (Proposed): Upright (Hurt is Upright), not a Hand, not
## carrying, with a free hand. A door never shuts on a body in its doorway: the action waits, still
## held, until the doorway clears. New doors start shut (mine.air_door_initial_shut); every state is
## kept by door (cell and barrier) across eviction and return, and every flip goes to the diff log
## (GEN-13 takes it over). Stage WORLD.

enum Pass { ALLOW = 0, HOLD = 1, DENY = 2 }

## The bodies that keep a door from shutting: miners in any state, Bess and the creatures.
const BODY_KINDS: Array[WorldIds.EntityKind] = [WorldIds.EntityKind.MINER, WorldIds.EntityKind.BESS,
	WorldIds.EntityKind.MOTH, WorldIds.EntityKind.TAPPER, WorldIds.EntityKind.TAPPER_ARM, WorldIds.EntityKind.STYTHE]


class Door:
	extends RefCounted
	var cell: Vector2i = Vector2i.ZERO
	var barrier: int = 0
	var tiles: Array[Vector2i] = []
	var open: bool = false

	func key() -> String:
		return "%d,%d:%d" % [cell.x, cell.y, barrier]

	func centre() -> Vector2:
		var sum: Vector2 = Vector2.ZERO
		for t: Vector2i in tiles:
			sum += Vector2(t) + Vector2(0.5, 0.5)
		return sum / maxf(1.0, tiles.size())

	func overlaps(p: Vector2, r: float) -> bool:
		for t: Vector2i in tiles:
			var nearest: Vector2 = Vector2(clampf(p.x, t.x, t.x + 1.0), clampf(p.y, t.y, t.y + 1.0))
			if p.distance_squared_to(nearest) < r * r:
				return true
		return false

	func near(p: Vector2, reach: float) -> bool:
		for t: Vector2i in tiles:
			if p.distance_to(Vector2(t) + Vector2(0.5, 0.5)) <= reach:
				return true
		return false


## GEN-13: a door's diff-log key is this and its key.
const DIFF_PREFIX: String = "door:"

## Doors in loaded cells, by key.
var doors: Dictionary = {}
## Every door's state ever set, by key (kept while its cell is evicted; GEN-13 saves it).
var states: Dictionary = {}
## The diff log's door entries: {tick, door, open}.
var diff_log: Array[Dictionary] = []
## actor -> [door key, ticks held]
var actions: Dictionary = {}
var _run: RunState = null


func stage() -> int:
	return StageTable.Stage.WORLD


func order() -> int:
	return 45


func system_name() -> String:
	return "air_doors"


func bind(run: RunState) -> void:
	_run = run
	if run.mine == null:
		return
	run.mine.native.cell_loaded.connect(_on_cell_loaded)
	run.mine.native.cell_unloading.connect(_on_cell_unloading)
	for cell: Vector2i in run.mine.native.loaded_cells():
		_on_cell_loaded(cell)
	if run.inventory != null:
		run.inventory.targets.providers.append(_door_targets)
	if run.diff_log != null:
		run.diff_log.register(DiffLog.Kind.BARRIER, _replay_door, Callable(), _door_default, DIFF_PREFIX)


func door_at(tile: Vector2i) -> Door:
	for raw: Variant in doors.values():
		var d: Door = raw
		if d.tiles.has(tile):
			return d
	return null


func _on_cell_loaded(cell: Vector2i) -> void:
	for raw: Variant in _run.mine.native.barriers(cell):
		var b: Dictionary = raw
		if int(Variants.number(b["material"])) != WorldIds.TileMaterial.WOODEN_DOOR:
			continue
		var d: Door = Door.new()
		d.cell = cell
		d.barrier = int(Variants.number(b["id"]))
		for t: Variant in Variants.array(b["tiles"]):
			d.tiles.append(t)
		var k: String = d.key()
		var want_open: bool = Variants.flag(states[k]) if states.has(k) else not Tuning.b(&"mine.air_door_initial_shut")
		doors[k] = d
		states[k] = want_open
		_apply(d, want_open)


func _on_cell_unloading(cell: Vector2i) -> void:
	for raw: Variant in doors.keys():
		var d: Door = doors[raw]
		if d.cell == cell:
			doors.erase(raw)


## Who may work a door: a miner, Upright (Hurt included), not a Hand, not carrying, with a free hand.
func may_work(run: RunState, entity: int) -> bool:
	var e: SimEntity = run.registry.get_entity(entity)
	if e == null or e.kind != WorldIds.EntityKind.MINER:
		return false
	if run.crew != null and Variants.flag(run.crew.is_hand_driven.call(entity)):
		return false
	if run.miner_state != null and run.miner_state.miner(entity) != null and run.miner_state.life(entity) != MinerTransitions.Life.UPRIGHT:
		return false
	if run.carry != null and run.carry.is_carrying(entity):
		return false
	if run.inventory != null and run.inventory.free_hand_blocked(entity, &"door"):
		return false
	return true


## True while any body overlaps the door's doorway.
func occupied(run: RunState, d: Door) -> bool:
	if CreatureNav.creature_in_doorway(run, d.tiles):
		return true
	var ids: Array = Array(run.registry.ids())
	ids.sort()
	for raw: Variant in ids:
		var e: SimEntity = run.registry.get_entity(int(Variants.number(raw)))
		if not BODY_KINDS.has(e.kind):
			continue
		var r: float = run.creatures.body_radius_of(e) if run.creatures != null else Tuning.f(&"movement.body_radius")
		if r > 0.0 and d.overlaps(e.position, r):
			return true
	return false


## The pass rule at a shut door, for CRT-02's navigation and its users (Gameplay §7.2, §7.4, §13.9):
## {result: Pass, seconds}. Open doors let everyone through.
static func request_pass(d: Door, mover: WorldIds.EntityKind) -> Dictionary:
	if d.open:
		return {"result": Pass.ALLOW, "seconds": 0.0}
	match mover:
		WorldIds.EntityKind.MOTH:
			return {"result": Pass.HOLD, "seconds": Tuning.f(&"moth.air_door_hold_s")}
		WorldIds.EntityKind.TAPPER, WorldIds.EntityKind.TAPPER_ARM:
			return {"result": Pass.ALLOW, "seconds": 0.0}  # in the rock: doors never matter
	# A miner must open it (a Hired Hand never does, and is left behind); to the Stythe, Bess and
	# anything else it is a wall.
	return {"result": Pass.DENY, "seconds": 0.0}


func tick(run: RunState) -> void:
	if run.movement == null or run.inputs == null:
		return
	var need: int = maxi(1, roundi(Tuning.f(&"mine.air_door_operate_s") * Tuning.f(&"net.tick_hz")))
	var reach: float = Tuning.f(&"vision.touch_range_tiles")
	var keep: Dictionary = {}
	for slot: int in run.movement.miner_slots():
		var actor: int = run.movement.miner(slot).entity_id
		# Cheapest first: most miners are not holding interact, and target picking is not free.
		if doors.is_empty() or not _holding(run, slot) or not may_work(run, actor):
			continue
		var d: Door = _target(run, actor, slot, reach)
		if d == null:
			continue
		var held: Array = Variants.array(actions.get(actor, []))
		var ticks: int = int(Variants.number(held[1])) if not held.is_empty() and str(held[0]) == d.key() else 0
		if ticks > need:
			keep[actor] = [d.key(), ticks]  # done: nothing more until the hold is released
			continue
		if ticks < need:
			ticks += 1
		if ticks < need:
			keep[actor] = [d.key(), ticks]
			continue
		if d.open and occupied(run, d):
			keep[actor] = [d.key(), need]  # the shutting waits, still held, for the doorway to clear
			continue
		_flip(run, d, not d.open)
		keep[actor] = [d.key(), need + 1]
	actions = keep


func _flip(run: RunState, d: Door, to_open: bool) -> void:
	states[d.key()] = to_open
	_apply(d, to_open)
	diff_log.append({"tick": run.tick, "door": d.key(), "open": to_open})
	if run.diff_log != null:
		run.diff_log.record(d.cell, DiffLog.Kind.BARRIER, DIFF_PREFIX + d.key(), {"open": to_open})


## GEN-13: a door's recorded state, put back when its cell is committed (or a save resumes).
func _replay_door(_r: RunState, _cell: Vector2i, key: String, p: Dictionary, _t: int) -> void:
	var k: String = key.trim_prefix(DIFF_PREFIX)
	var want_open: bool = Variants.flag(p.get("open", false))
	states[k] = want_open
	if doors.has(k):
		var d: Door = doors[k]
		# Its own load hook has usually applied the state already: no second barrier change.
		if d.open != want_open:
			_apply(d, want_open)


## A door as generated (mine.air_door_initial_shut) needs no record.
func _door_default(_cell: Vector2i, _key: String, p: Dictionary) -> bool:
	return Variants.flag(p.get("open", false)) != Tuning.b(&"mine.air_door_initial_shut")


func _apply(d: Door, to_open: bool) -> void:
	d.open = to_open
	_run.mine.native.set_barrier(d.cell, d.barrier, to_open)


## The door the actor works: the interaction target when it is a door, within touch range.
func _target(run: RunState, actor: int, slot: int, reach: float) -> Door:
	var e: SimEntity = run.registry.get_entity(actor)
	if e == null:
		return null
	if run.inventory != null:
		var t: Dictionary = run.inventory.targets.pick(run, actor, slot, run.inventory.world)
		if t.is_empty() or StringName(str(t["kind"])) != &"air_door":
			return null
		return Variants.dict(doors).get(str(t["door"]), null)
	for raw: Variant in doors.values():
		var d: Door = raw
		if d.near(e.position, reach):
			return d
	return null


## MNR-04's interaction targets: every door within touch range.
func _door_targets(_r: RunState, _actor: int, at: Vector2, reach: float) -> Array:
	var out: Array = []
	var keys: Array = doors.keys()
	keys.sort()
	for i: int in keys.size():
		var d: Door = doors[keys[i]]
		if d.near(at, reach):
			out.append({"kind": &"air_door", "id": i, "door": d.key(), "point": d.centre()})
	return out


func _holding(run: RunState, slot: int) -> bool:
	var c: InputBuffer.Consumed = run.inputs.input_for(slot)
	return c != null and (c.record.holds & InputRecord.HOLD_INTERACT) != 0


func write_state(writer: SimStateWriter) -> void:
	var keys: Array = states.keys()
	keys.sort()
	writer.put_i64(keys.size())
	for k: Variant in keys:
		writer.put_string(str(k))
		writer.put_bool(Variants.flag(states[k]))
	var actors: Array = actions.keys()
	actors.sort()
	writer.put_i64(actors.size())
	for a: Variant in actors:
		writer.put_i64(int(Variants.number(a)))
		writer.put_i64(int(Variants.number(Variants.array(actions[a])[1])))
	writer.put_i64(diff_log.size())
