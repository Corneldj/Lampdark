class_name Stones
extends SimSystem
## MNR-09 (stage MINERS, after the flares): stones (Gameplay §4.5, §6.1, §8.2; GDD §15.8). Interact at
## a rubble heap (a map anchor "rubble_heap") takes one in items.pick_up_time, to the belt (3 a
## slot); heaps never run out (Proposed). ActionRecord.Kind.THROW (Use released on the stone slot)
## throws one along the miner's facing, its distance the client's cursor distance or stick
## deflection clamped to items.stone_throw_min-max. It flies a fixed arc at items.stone_flight_speed
## (no physics) and is spent (Proposed); rock, a closed air door or a shut gate before the distance
## stops it, and it lands on the last open tile. Landing is a stone_landing event (14 np) at that
## tile whose true source is no miner, so nobody is beside it unless it fell short; `landed` tells
## HAZ-01 (a set man-trap there springs). Nothing of the flight or the landing point is ever sent:
## no mark, no arc, no reticle. None while both hands are full, Grabbed or unconscious, or with the
## free hand blocked (a drawn revolver, a can, a burning flare); Caught miners may. Server-only.

## A stone came down at a tile (HAZ-01's man-traps spring under it).
signal landed(tile: Vector2i)

## Rubble heap tiles: tile -> true.
var heaps: Dictionary = {}
## Stones in the air: {land_tick, tile, thrower, distance, short}.
var flying: Array[Dictionary] = []
## Every throw, refused ones included: {tick, miner, asked, distance, tile, land_tick, refused}.
var throws: Array[Dictionary] = []
## Every landing: {tick, tile, event}.
var landings: Array[Dictionary] = []
var _scanned: Dictionary = {}
var _loaded_count: int = -1
var _run: RunState = null


func stage() -> int:
	return StageTable.Stage.MINERS


func order() -> int:
	return 34


func system_name() -> String:
	return "stones"


func bind(run: RunState) -> void:
	_run = run
	if run.inventory != null:
		run.inventory.targets.providers.append(_heap_targets)


## A rubble heap at `tile` (GEN-10's placement; tests).
func add_heap(tile: Vector2i) -> void:
	heaps[tile] = true


func tick(run: RunState) -> void:
	_run = run
	_scan_heaps(run)
	_land(run)
	if run.movement == null or run.inventory == null:
		return
	for slot: int in run.movement.miner_slots():
		var actor: int = run.movement.miner(slot).entity_id
		var c: InputBuffer.Consumed = run.input_for(slot)
		if c == null:
			continue
		for a: ActionRecord in c.actions:
			if a.kind == ActionRecord.Kind.THROW:
				throw(run, actor, slot, a.arg / 100.0)
		if run.inventory.actions.has(actor) or not run.inventory.is_fresh(actor, c.record.holds, InputRecord.HOLD_INTERACT):
			continue
		var t: Dictionary = run.inventory.targets.pick(run, actor, slot, run.inventory.world)
		if t.is_empty() or StringName(str(t["kind"])) != &"rubble":
			continue
		run.inventory.mark_spent(actor, InputRecord.HOLD_INTERACT)
		var point: Vector2 = t["point"]
		run.inventory.start_action(run, take_action(run, actor, point))


## Taking a stone from the heap at `point`: MNR-04's pick-up time, interact held, in touch range;
## refused while the free hand is blocked or the belt has no room for a stone.
func take_action(run: RunState, actor: int, point: Vector2) -> TimedAction:
	var a: TimedAction = TimedAction.make(actor, &"take_stone", Tuning.f(&"items.pick_up_time"), InputRecord.HOLD_INTERACT)
	a.target_point = point
	a.reach = Tuning.f(&"vision.touch_range_tiles")
	var probe: Item = Item.make(0, ItemKinds.Kind.STONE)
	a.valid = func() -> bool:
		return not run.inventory.free_hand_blocked(actor, &"pick_up") and run.inventory.hands_of(actor).fits(probe)
	a.effect = func() -> void:
		run.inventory.give(run, actor, run.inventory.world.make(ItemKinds.Kind.STONE))
	return a


## Throws the selected slot's stone `asked` tiles along the facing (clamped). False if refused.
func throw(run: RunState, actor: int, slot: int, asked: float) -> bool:
	var h: HandsAndBelt = run.inventory.hands_of(actor)
	var stone: Item = h.slots[h.selected] if h.selected < h.slots.size() else null
	var row: Dictionary = {"tick": run.tick, "miner": actor, "asked": asked, "refused": true}
	throws.append(row)
	if stone == null or stone.kind != ItemKinds.Kind.STONE or h.two_handed or run.inventory.actions.has(actor):
		return false
	if run.inventory.free_hand_blocked(actor, &"throw"):
		return false
	if run.miner_state != null and run.miner_state.miner(actor) != null and not Variants.flag(run.miner_state.capabilities(actor)["belt"]):
		return false
	var distance: float = clampf(asked, Tuning.f(&"items.stone_throw_min"), Tuning.f(&"items.stone_throw_max"))
	var me: SimEntity = run.registry.get_entity(actor)
	var flight: Dictionary = flight_of(run, me.position, run.movement.facing_of(slot), distance)
	stone.count -= 1
	if stone.count == 0:
		h.slots[h.selected] = null
	run.inventory.world.note(run, &"thrown", stone, actor)
	run.inventory.changed.emit(actor)
	var flown: float = float(Variants.number(flight["flown"]))
	var land_tick: int = run.tick + maxi(1, ceili(flown / Tuning.f(&"items.stone_flight_speed") * Tuning.f(&"net.tick_hz")))
	var tile: Vector2i = flight["tile"]
	flying.append({"land_tick": land_tick, "tile": tile, "thrower": actor, "distance": flown})
	row["refused"] = false
	row["distance"] = distance
	row["tile"] = tile
	row["land_tick"] = land_tick
	return true


## The fixed arc along `facing` (u16) from `from`: the last open tile within `distance`, stopped by
## rock, a closed air door or a shut gate. {tile, flown}.
static func flight_of(run: RunState, from: Vector2, facing: int, distance: float) -> Dictionary:
	var u: PackedFloat64Array = LbDetMath.unit(float(facing) / 65536.0)
	var dir: Vector2 = Vector2(u[0], u[1])
	var start: Vector2i = Vector2i(floori(from.x), floori(from.y))
	var last: Vector2i = start
	var flown: float = 0.0
	var step: float = 0.05
	var steps: int = ceili(distance / step)
	for i: int in range(1, steps + 1):
		var d: float = minf(i * step, distance)
		var p: Vector2 = from + dir * d
		var t: Vector2i = Vector2i(floori(p.x), floori(p.y))
		if t != last and run.mine != null and not run.mine.native.is_walkable(t, false):
			break
		last = t
		flown = d
	return {"tile": last, "flown": flown}


func _land(run: RunState) -> void:
	var still: Array[Dictionary] = []
	for f: Dictionary in flying:
		if int(Variants.number(f["land_tick"])) > run.tick:
			still.append(f)
			continue
		var tile: Vector2i = f["tile"]
		# The true source is no miner: the landing lures with nobody beside it.
		var id: int = run.noise.emit(NoiseTypes.Type.STONE_LANDING, tile, {"source": 0}) if run.noise != null else 0
		landings.append({"tick": run.tick, "tile": tile, "event": id})
		landed.emit(tile)
	flying = still


## Rubble heaps in reach, as interaction targets (UI-01's prompt reads the same pick).
func _heap_targets(_r: RunState, _actor: int, at: Vector2, reach: float) -> Array:
	var out: Array = []
	var here: Vector2i = Vector2i(floori(at.x), floori(at.y))
	var span: int = ceili(reach) + 1
	for dy: int in range(-span, span + 1):
		for dx: int in range(-span, span + 1):
			var t: Vector2i = here + Vector2i(dx, dy)
			if not heaps.has(t):
				continue
			var p: Vector2 = Vector2(t) + Vector2(0.5, 0.5)
			if p.distance_to(at) <= reach:
				out.append({"kind": &"rubble", "id": (t.y << 16) ^ (t.x & 0xFFFF), "point": p})
	return out


## Rubble heap anchors in every loaded cell (rescanned when the loaded set changes).
func _scan_heaps(run: RunState) -> void:
	if run.mine == null:
		return
	var cells: Array = run.mine.native.loaded_cells()
	if cells.size() == _loaded_count:
		return
	_loaded_count = cells.size()
	for raw: Variant in cells:
		var cell: Vector2i = raw
		if _scanned.has(cell):
			continue
		_scanned[cell] = true
		for a: Dictionary in run.mine.native.anchors(cell):
			if str(a.get("type", "")) != "rubble_heap":
				continue
			var x: int = int(Variants.number(a["x"]))
			var y: int = int(Variants.number(a["y"]))
			for dy: int in maxi(1, int(Variants.number(a.get("h", 1)))):
				for dx: int in maxi(1, int(Variants.number(a.get("w", 1)))):
					heaps[WorldCoords.tile_of(cell, Vector2i(x + dx, y + dy))] = true


func write_state(writer: SimStateWriter) -> void:
	writer.put_i64(flying.size())
	for f: Dictionary in flying:
		writer.put_i64(int(Variants.number(f["land_tick"])))
		var t: Vector2i = f["tile"]
		writer.put_i64(t.x)
		writer.put_i64(t.y)
