class_name GateSystem
extends SimSystem
## LFT-02: base camp's three security gates (stage WORLD, before BaseCampState so a flip's
## sealed_changed fires the same tick). Levers on either side open or shut a gate in
## basecamp.gate_lever_s; the flip lands in one tick on the action's last tick: GEN-01's barrier
## (which SND-01's portal, VIS-02 and VIS-03 read), the spill (with the doorway itself lit at base
## camp's level, so no dark gap lies between), the diff log, then one 14 np clang.
## A gate never shuts on a body in its doorway; in public runs an unheld gate swings shut
## basecamp.gate_public_autoclose_s after opening. Only conscious miners with a free hand work a
## lever: never a Hand, Bess or a creature (none has an input slot, and Hands are refused).
## Server-only: gate states reach clients only as geometry; timers and holders never leave here.

signal flipped(side: String, open: bool)
signal jammed(side: String)

## The bodies that keep a gate from shutting (GDD §15.8): miners in any state (Hands and the
## fallen are miners), Bess and the creatures.
const BODY_KINDS: Array[WorldIds.EntityKind] = [WorldIds.EntityKind.MINER, WorldIds.EntityKind.BESS,
	WorldIds.EntityKind.MOTH, WorldIds.EntityKind.TAPPER, WorldIds.EntityKind.TAPPER_ARM, WorldIds.EntityKind.STYTHE]
const SPILL_KIND: String = "gate_spill"
## Base camp's cell (GEN-02).
const CELL: Vector2i = Vector2i.ZERO

var gates: Array[Gate] = []
## The diff log's gate entries (GEN-13 takes them over): {tick, side, open}.
var diff_log: Array[Dictionary] = []
## An extra free-hand test (tests force it false); MNR-04's own rule is always applied too.
var free_hand: Callable = func(_entity: int) -> bool: return true
var _cell_loaded: bool = false


func stage() -> int:
	return StageTable.Stage.WORLD


func order() -> int:
	return 40


func system_name() -> String:
	return "GateSystem"


## Builds the gates from GEN-02's specs. `fresh`: run creation, every gate shut (the cell is
## authored open); a resume restores them with restore() instead.
func install(run: RunState, specs: Array[Dictionary], fresh: bool) -> void:
	gates.clear()
	for spec: Dictionary in specs:
		gates.append(Gate.from_spec(spec))
	_cell_loaded = run.mine != null and run.mine.native.is_loaded(CELL)
	if run.inventory != null:
		run.inventory.targets.providers.append(_lever_targets)
	if fresh:
		for g: Gate in gates:
			_apply(run, g, false)


func gate(side: String) -> Gate:
	for g: Gate in gates:
		if g.side == side:
			return g
	return null


## The diff log's record of every gate, for eviction and resume.
func snapshot() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for g: Gate in gates:
		out.append(g.to_record())
	return out


## A resume: each gate back to its recorded state, quietly (no clang, no diff-log entry).
func restore(run: RunState, records: Array[Dictionary]) -> void:
	for r: Dictionary in records:
		var g: Gate = gate(str(r["side"]))
		if g == null:
			continue
		g.opened_tick = int(Variants.number(r["opened_tick"]))
		_apply(run, g, Variants.flag(r["open"]))


## Who may work a lever (Gameplay §3.2, §13.9): a conscious miner (Upright or Caught), not a
## Hand, with a free hand. Bess and the creatures are never miners.
func may_work(run: RunState, entity: int) -> bool:
	var e: SimEntity = run.registry.get_entity(entity)
	if e == null or e.kind != WorldIds.EntityKind.MINER:
		return false
	if run.crew != null and Variants.flag(run.crew.is_hand_driven.call(entity)):
		return false
	if run.miner_state != null:
		var life: int = run.miner_state.life(entity)
		if life != MinerTransitions.Life.UPRIGHT and life != MinerTransitions.Life.CAUGHT:
			return false
	if run.inventory != null and run.inventory.free_hand_blocked(entity, &"lever"):
		return false
	return Variants.flag(free_hand.call(entity))


## True while any body overlaps the gate's doorway.
func occupied(run: RunState, g: Gate) -> bool:
	if CreatureNav.creature_in_doorway(run, g.tiles):
		return true
	var ids: Array = Array(run.registry.ids())
	ids.sort()
	for raw: Variant in ids:
		var e: SimEntity = run.registry.get_entity(int(Variants.number(raw)))
		if not BODY_KINDS.has(e.kind):
			continue
		var r: float = run.creatures.body_radius_of(e) if run.creatures != null else Tuning.f(&"movement.body_radius")
		if r > 0.0 and g.overlaps(e.position, r):
			return true
	return false


func tick(run: RunState) -> void:
	_follow_world(run)
	_levers(run)
	_hold_and_autoclose(run)


## The lever actions: interact held within touch range of a lever runs that gate's action; the
## gate flips (or jams) on its last tick. Released early, or no longer allowed, nothing happens.
func _levers(run: RunState) -> void:
	if run.movement == null or run.inputs == null:
		return
	var need: int = roundi(Tuning.f(&"basecamp.gate_lever_s") * Tuning.f(&"net.tick_hz"))
	var reach: float = Tuning.f(&"vision.touch_range_tiles")
	for actor: int in _miners(run):
		var at: Vector2 = run.registry.get_entity(actor).position
		var target: Gate = null
		var lever: Vector2i = Vector2i.ZERO
		if _holding(run, actor) and may_work(run, actor) and _lever_is_target(run, actor):
			var best_d: float = INF
			for g: Gate in gates:
				var near: Variant = g.lever_near(at, reach)
				if near == null:
					continue
				var tile: Vector2i = near
				var d: float = at.distance_to(Vector2(tile) + Vector2(0.5, 0.5))
				if d < best_d:
					best_d = d
					target = g
					lever = tile
		for g: Gate in gates:
			if g != target:
				g.actions.erase(actor)
				g.holders.erase(actor)
		if target == null or target.holders.has(actor):
			continue
		var action: Gate.LeverAction = target.actions.get(actor, null)
		if action == null or action.lever != lever:
			action = Gate.LeverAction.new()
			action.actor = actor
			action.lever = lever
			action.started_tick = run.tick
			target.actions[actor] = action
		action.ticks_done += 1
		if action.ticks_done < need:
			continue
		target.actions.erase(actor)
		target.holders[actor] = true
		if not target.open:
			_flip(run, target, true)
		elif occupied(run, target):
			jammed.emit(target.side)
		else:
			_flip(run, target, false)


## Holders keep holding while interact stays held, in touch range of either lever and allowed;
## a public gate past its time, unheld and clear, swings shut.
func _hold_and_autoclose(run: RunState) -> void:
	var reach: float = Tuning.f(&"vision.touch_range_tiles")
	var public: bool = run.header.mode == ServerConfig.Mode.PUBLIC
	var after: int = roundi(Tuning.f(&"basecamp.gate_public_autoclose_s") * Tuning.f(&"net.tick_hz"))
	for g: Gate in gates:
		var keep: Dictionary = {}
		for raw: Variant in g.holders.keys():
			var actor: int = int(Variants.number(raw))
			var e: SimEntity = run.registry.get_entity(actor)
			if e != null and _holding(run, actor) and may_work(run, actor) and g.lever_near(e.position, reach) != null:
				keep[actor] = true
		g.holders = keep
		if not public or not g.open or not g.holders.is_empty() or run.tick - g.opened_tick < after:
			continue
		if not occupied(run, g):
			_flip(run, g, false)


func _flip(run: RunState, g: Gate, to_open: bool) -> void:
	if not to_open:
		_clear_items(run, g)
	_apply(run, g, to_open)
	if to_open:
		g.opened_tick = run.tick
	for raw: Variant in g.actions.keys():
		g.holders[int(Variants.number(raw))] = true
	g.actions.clear()
	diff_log.append({"tick": run.tick, "side": g.side, "open": to_open})
	if run.noise != null:
		run.noise.emit(NoiseTypes.Type.GATE, g.middle(), {"origins": g.clang_origins()})
	flipped.emit(g.side, to_open)


## The barrier and the spill, with no event: install, resume and a reloaded cell use it alone.
func _apply(run: RunState, g: Gate, to_open: bool) -> void:
	g.open = to_open
	if not to_open:
		g.opened_tick = -1
	if run.mine != null and run.mine.native.is_loaded(CELL):
		run.mine.native.set_barrier(CELL, g.barrier, to_open)
	if run.light == null:
		return
	if to_open and g.spill == 0:
		var doorway: Array = []
		for t: Vector2i in g.tiles:
			doorway.append(t)
		var level: float = Tuning.f(&"basecamp.emergency_light_level")
		g.doorway_light = run.light.grid.add_area(SPILL_KIND, LbLightGrid.COLOUR_WHITE, 0, level, doorway)
		g.spill = run.light.grid.add_spill(SPILL_KIND, LbLightGrid.COLOUR_WHITE, 0, doorway, g.outward,
			Tuning.f(&"basecamp.gate_spill_tiles"), level, Tuning.f(&"light.edge_value"))
	elif not to_open and g.spill != 0:
		run.light.grid.remove_source(g.spill)
		run.light.grid.remove_source(g.doorway_light)
		g.spill = 0
		g.doorway_light = 0


## Loose items on a shutting doorway go to the floor on their nearer side, as in a collapse.
func _clear_items(run: RunState, g: Gate) -> void:
	var ids: Array = Array(run.registry.ids())
	ids.sort()
	var centre: Vector2 = Vector2(g.middle()) + Vector2(0.5, 0.5)
	for raw: Variant in ids:
		var e: SimEntity = run.registry.get_entity(int(Variants.number(raw)))
		if e.kind != WorldIds.EntityKind.ITEM or not g.tiles.has(e.tile()):
			continue
		var way: Vector2i = g.outward if (e.position - centre).dot(Vector2(g.outward)) >= 0.0 else -g.outward
		run.registry.move(e.id, Vector2(e.tile() + way) + Vector2(0.5, 0.5))


## Base camp's cell evicted and reloaded comes back as authored: the record is put back quietly.
## A change made to the tiles from outside (the debug console) is adopted.
func _follow_world(run: RunState) -> void:
	if run.mine == null:
		return
	var loaded: bool = run.mine.native.is_loaded(CELL)
	var reloaded: bool = loaded and not _cell_loaded
	_cell_loaded = loaded
	if not loaded:
		return
	for g: Gate in gates:
		var shut_tiles: bool = run.mine.native.effective_material(g.tiles[0]) == WorldIds.TileMaterial.STEEL
		if reloaded:
			_apply(run, g, g.open)
		elif shut_tiles == g.open:
			_apply(run, g, not shut_tiles)
			if g.open and g.opened_tick < 0:
				g.opened_tick = run.tick


## MNR-04's interaction targets: every lever in touch range is a candidate.
func _lever_targets(_run: RunState, _actor: int, at: Vector2, reach: float) -> Array:
	var out: Array = []
	for i: int in gates.size():
		var g: Gate = gates[i]
		for key: String in ["inside", "outside"]:
			if not g.levers.has(key):
				continue
			var tile: Vector2i = g.levers[key]
			var centre: Vector2 = Vector2(tile) + Vector2(0.5, 0.5)
			if at.distance_to(centre) <= reach:
				out.append({"kind": &"lever", "id": i * 2 + (0 if key == "inside" else 1), "point": centre})
	return out


## Interact works a lever only when a lever is the miner's interaction target (an item nearer the
## facing ray is picked up instead, MNR-04).
func _lever_is_target(run: RunState, actor: int) -> bool:
	if run.inventory == null:
		return true
	for slot: int in run.movement.miner_slots():
		if run.movement.miner(slot).entity_id == actor:
			var t: Dictionary = run.inventory.targets.pick(run, actor, slot, run.inventory.world)
			return not t.is_empty() and StringName(str(t["kind"])) == &"lever"
	return false


func _miners(run: RunState) -> Array[int]:
	var out: Array[int] = []
	for slot: int in run.movement.miner_slots():
		out.append(run.movement.miner(slot).entity_id)
	out.sort()
	return out


func _holding(run: RunState, entity: int) -> bool:
	for slot: int in run.movement.miner_slots():
		if run.movement.miner(slot).entity_id == entity:
			var c: InputBuffer.Consumed = run.inputs.input_for(slot)
			return c != null and (c.record.holds & InputRecord.HOLD_INTERACT) != 0
	return false


func write_state(writer: SimStateWriter) -> void:
	for g: Gate in gates:
		writer.put_bool(g.open)
		writer.put_i64(g.opened_tick)
		writer.put_i64(g.actions.size())
		writer.put_i64(g.holders.size())
	writer.put_i64(diff_log.size())
