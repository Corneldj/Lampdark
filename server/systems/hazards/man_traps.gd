class_name ManTraps
extends SimSystem
## HAZ-01 (Gameplay §8.2, §8.1, §11.3, §12.5, §8.3, §4.6, A.5): the men in-bye's steel jaws. GEN-10
## places them (kind man_trap): the homes' traps.man_trap_approach_min to _max on the roads into the
## Stythe's territory, and about one in traps.man_trap_cells_per cells of ring 2 and deeper. Each in
## a loaded cell is a TRAP entity, set or sprung:
## - **The tell:** VIS-03 shows it only at 0.30, a small thing and never a fringe token, sprung jaws
##   apart from set ones (the identity record's SeenKind.TRAP_SPRUNG); feeling names it ('[iron
##   jaws]', VIS-07) and never springs it.
## - **The trigger:** a standing miner's centre on a set trap's tile, at any gait, Hired Hands
##   included; never a creature, Bess, or a body being dragged or carried. A carrier springs it and
##   sets the load down at once. In the one tick: the snap at the trap (noise.mantrap_snap_np), the
##   victim's involuntary cry in their own voice (noise.trapped_cry_np, talk band), then RSC-03's
##   catch: Caught, and DIR-01's +15.
## - **Freeing:** a teammate's "Free" in MNR-05's ring, both hands (MNR-04 hooks the lamp), held for
##   traps.man_trap_free_s, or traps.man_trap_free_cutters_s with the wire cutters on the belt;
##   letting go early keeps nothing, and one freer works at a time. A POINTed Hired Hand frees in
##   hands.free_s (MOD-08's HandJobs); Hands never use tools, and never struggle. Alone, the victim
##   holds interact: traps.man_trap_struggle_s of holding in all, a struggle (noise.struggle_np)
##   every noise.struggle_interval_s while holding, pausing keeping the progress. The first to finish
##   frees; an unconscious victim waits for a teammate.
## - **Freed:** RSC-03's release. MNR-03 marked the trap wound when the jaws closed (every gait x0.8
##   until cured, never with Hurt's on top); TrapEvents says freed; the trap stays sprung. A Stythe's
##   drag tears a Caught miner out with the wound (RSC-03).
## - **On purpose:** any tool, traps.spring_with_tool_s from beside a known trap (MNR-12), or jaws
##   under a thrown stone (MNR-09): the same snap, the trap spent for the run, nobody caught.
## A sprung trap is GEN-13's TRAP record, so it stays sprung through eviction and resume. Server-only:
## nothing of a trap leaves it but its entity, seen as VIS-03 allows.

const KEY_PREFIX: String = "trap:"
## The ring's option (MNR-05) and the timed action it runs.
const FREE_OPTION: String = "free"
const FREE_VERB: StringName = &"free_jaws"


class Trap:
	extends RefCounted
	## GEN-10's placement id ("" for a trap laid by hand: tests, fixed maps), GEN-13's key.
	var pid: String = ""
	var cell: Vector2i = Vector2i.ZERO
	var tile: Vector2i = Vector2i.ZERO
	var entity: int = 0
	var sprung: bool = false


## entity -> Trap: every man-trap in a loaded cell.
var traps: Dictionary = {}
## Placement id -> true: the traps GEN-13 holds sprung, loaded or not.
var sprung_ids: Dictionary = {}
## victim -> ticks of struggle held so far.
var struggle: Dictionary = {}
## What happened: {tick, what ("caught", "spent", "freed"), trap, victim, by, how}.
var history: Array[Dictionary] = []
## Cells loaded since the last tick: their traps spawn then, once GEN-10's placements and GEN-13's
## replay are in.
var _pending: Array[Vector2i] = []
## MNR-12's hooks as they were (HAZ-02's staple pits share them): called for any other trap.
var _other_spring: Callable = Callable()
var _other_is_set: Callable = Callable()


func stage() -> int:
	return StageTable.Stage.WORLD


func order() -> int:
	return 61


func system_name() -> String:
	return "man_traps"


## Hashed once a trap is loaded or a struggle is under way, so a run without one hashes as before.
func hashed() -> bool:
	return not traps.is_empty() or not struggle.is_empty()


func bind(run: RunState) -> void:
	if run.mine != null:
		run.mine.native.cell_loaded.connect(func(cell: Vector2i) -> void:
			if not _pending.has(cell):
				_pending.append(cell))
		run.mine.native.cell_unloading.connect(func(cell: Vector2i) -> void: _on_unloading(run, cell))
		# NET-09: a resume's swap of the registry, each loaded cell's traps made again after it.
		run.cell_released.connect(func(cell: Vector2i) -> void: _on_unloading(run, cell))
		run.cell_remade.connect(func(cell: Vector2i) -> void:
			if not _pending.has(cell):
				_pending.append(cell))
	if run.diff_log != null:
		run.diff_log.register(DiffLog.Kind.TRAP, _replay, Callable(),
			func(_cell: Vector2i, _key: String, p: Dictionary) -> bool: return not Variants.flag(p.get("sprung", false)), KEY_PREFIX)
	if run.holds != null:
		run.holds.caught_ended.connect(func(_trap: int, _outcome: CaughtHold.Outcome, victim: int) -> void: struggle.erase(victim))
	if run.stones != null:
		run.stones.landed.connect(func(tile: Vector2i) -> void:
			var t: Trap = set_trap_at(tile)
			if t != null:
				spring_empty(run, t, 0, "stone"))
	if run.tools_parts != null:
		_other_spring = run.tools_parts.spring_on_purpose
		_other_is_set = run.tools_parts.trap_is_set
		run.tools_parts.spring_on_purpose = func(r: RunState, trap: int, by: int) -> void:
			var t: Trap = traps.get(trap, null)
			if t != null:
				spring_empty(r, t, by, "tool")
			elif _other_spring.is_valid():
				_other_spring.call(r, trap, by)
		run.tools_parts.trap_is_set = func(r: RunState, trap: int) -> bool:
			var t: Trap = traps.get(trap, null)
			if t != null:
				return not t.sprung
			return _other_is_set.is_valid() and Variants.flag(_other_is_set.call(r, trap))
	if run.ring != null:
		var held: Array[int] = [MinerTransitions.Life.CAUGHT, MinerTransitions.Life.UNCONSCIOUS]
		run.ring.registry.register(FREE_OPTION, held,
			func(r: RunState, actor: int, target: int) -> bool: return may_free(r, actor, target),
			func(r: RunState, actor: int, target: int) -> TimedAction: return free_action(r, actor, target))


## A man-trap on `tile` (a tile centre; `pid` its placement id, GEN-13's key). Returns its entity.
func place(run: RunState, tile: Vector2i, pid: String = "") -> int:
	var t: Trap = Trap.new()
	t.pid = pid
	t.cell = WorldCoords.cell_of(tile)
	t.tile = tile
	t.sprung = not pid.is_empty() and sprung_ids.has(pid)
	t.entity = run.registry.create(WorldIds.EntityKind.TRAP, Vector2(tile) + Vector2(0.5, 0.5)).id
	traps[t.entity] = t
	_show(run, t)
	return t.entity


static func is_caught(run: RunState, victim: int) -> bool:
	if run.holds == null:
		return false
	var h: CaughtHold = run.holds.caught_in(victim)
	return h != null and h.kind == CaughtHold.Kind.MAN_TRAP


func is_set(entity: int) -> bool:
	var t: Trap = traps.get(entity, null)
	return t != null and not t.sprung


## The set trap on `tile`, or null.
func set_trap_at(tile: Vector2i) -> Trap:
	for raw: Variant in _sorted_ids():
		var t: Trap = traps[raw]
		if t.tile == tile and not t.sprung:
			return t
	return null


func tick(run: RunState) -> void:
	_spawn_pending(run)
	_trigger(run)
	_struggles(run)


#region The trigger

## Every standing miner (Hands too) on a set trap's tile springs it; bodies and creatures never do.
func _trigger(run: RunState) -> void:
	if traps.is_empty() or run.movement == null:
		return
	var ids: Array[int] = []
	for slot: int in run.movement.miner_slots():
		ids.append(run.movement.miner(slot).entity_id)
	ids.sort()
	for m: int in ids:
		if not run.registry.has(m):
			continue
		if run.miner_state != null and run.miner_state.miner(m) != null and run.miner_state.life(m) != MinerTransitions.Life.UPRIGHT:
			continue
		var t: Trap = set_trap_at(run.registry.get_entity(m).tile())
		if t != null:
			spring_on(run, t, m)


## The jaws close on `victim`: a carrier's load set down, the snap, the cry, the catch.
func spring_on(run: RunState, t: Trap, victim: int) -> void:
	if run.carry != null and run.carry.is_carrying(victim):
		run.carry.set_down(run, victim)
	if run.loads != null and run.loads.carrying(victim):
		run.loads.set_down(run, victim)
	if run.tubs != null and run.tubs.holding(victim):
		run.tubs.let_go(run, victim)
	_spend(run, t)
	if run.noise != null:
		run.noise.emit(NoiseTypes.Type.MANTRAP_SNAP, t.tile, {"source": t.entity})
		run.noise.emit(NoiseTypes.Type.TRAPPED_CRY, t.tile, {"source": victim})
	if run.holds != null:
		run.holds.catch(run, victim, CaughtHold.Kind.MAN_TRAP, t.entity)
	history.append({"tick": run.tick, "what": "caught", "trap": t.entity, "victim": victim})
	Log.info("man-trap %d: miner %d caught" % [t.entity, victim])


## Sprung with nobody in it (a tool from beside it, or a stone under its jaws): the snap, spent.
func spring_empty(run: RunState, t: Trap, by: int, how: String) -> void:
	if t.sprung:
		return
	_spend(run, t)
	if run.noise != null:
		run.noise.emit(NoiseTypes.Type.MANTRAP_SNAP, t.tile, {"source": t.entity})
	history.append({"tick": run.tick, "what": "spent", "trap": t.entity, "by": by, "how": how})


func _spend(run: RunState, t: Trap) -> void:
	t.sprung = true
	_show(run, t)
	if t.pid.is_empty():
		return
	sprung_ids[t.pid] = true
	if run.diff_log != null:
		run.diff_log.record(t.cell, DiffLog.Kind.TRAP, KEY_PREFIX + t.pid, {"sprung": true})

#endregion

#region Freeing

## A teammate may free `target`: caught in a man-trap; the actor another miner, standing, not a Hired
## Hand (a POINTed Hand frees through HandJobs), a hand free to take the jaws in both; nobody freeing
## them already.
func may_free(run: RunState, actor: int, target: int) -> bool:
	if actor == target or not is_caught(run, target) or _hand(run, actor) or _freer_of(run, target) != 0:
		return false
	if run.miner_state != null and run.miner_state.miner(actor) != null and run.miner_state.life(actor) != MinerTransitions.Life.UPRIGHT:
		return false
	if run.inventory == null:
		return true
	var h: HandsAndBelt = run.inventory.hands_of(actor)
	return h != null and h.free_hand == null and not h.two_handed


## The free, two-handed: traps.man_trap_free_s, or traps.man_trap_free_cutters_s with the wire cutters
## on the belt from the start; the lamp hooked while it runs, unhooked if let go.
func free_action(run: RunState, actor: int, target: int) -> TimedAction:
	var cutters: bool = run.tools_parts != null and run.tools_parts.has_tool(run, [actor], ItemKinds.Kind.WIRE_CUTTERS)
	var seconds: float = Tuning.f(&"traps.man_trap_free_cutters_s") if cutters else Tuning.f(&"traps.man_trap_free_s")
	var a: TimedAction = TimedAction.make(actor, FREE_VERB, seconds, InputRecord.HOLD_INTERACT)
	a.target_entity = target
	a.reach = Tuning.f(&"vision.touch_range_tiles")
	var hooked: Array[bool] = [false]
	a.on_start = func() -> void:
		hooked[0] = run.inventory != null and run.inventory.begin_two_handed(run, actor)
	a.valid = func() -> bool:
		return is_caught(run, target) and (hooked[0] or run.inventory == null) \
			and (not cutters or run.tools_parts.has_tool(run, [actor], ItemKinds.Kind.WIRE_CUTTERS))
	var unhook: Callable = func() -> void:
		if hooked[0]:
			hooked[0] = false
			run.inventory.end_two_handed(actor)
	a.cancelled.connect(func(_action: TimedAction, _reason: StringName) -> void: unhook.call())
	a.effect = func() -> void:
		unhook.call()
		free_victim(run, target, "cutters" if cutters else "hands", actor)
	return a


## The miner freeing `target` now (their free under way), or 0.
static func _freer_of(run: RunState, target: int) -> int:
	if run.inventory == null:
		return 0
	for raw: Variant in run.inventory.actions.keys():
		var a: TimedAction = run.inventory.actions[raw]
		if a.verb == FREE_VERB and a.target_entity == target:
			return Variants.whole(raw)
	return 0


## Whether the miner may struggle free (StatusWire's key hint): in a man-trap, conscious, a player's own.
static func may_struggle(run: RunState, miner: int) -> bool:
	return is_caught(run, miner) and not _hand(run, miner) and run.miner_state != null \
		and run.miner_state.life(miner) == MinerTransitions.Life.CAUGHT


## The lone struggle: each tick a conscious caught miner holds interact (with no action of their own
## but feeling, no ring open), a tick of progress; a struggle sounds every interval of holding.
func _struggles(run: RunState) -> void:
	if run.holds == null:
		return
	var victims: Array = run.holds.caught.keys()
	victims.sort()
	var interval: int = maxi(1, roundi(Tuning.f(&"noise.struggle_interval_s") * Tuning.f(&"net.tick_hz")))
	var needed: int = maxi(1, roundi(Tuning.f(&"traps.man_trap_struggle_s") * Tuning.f(&"net.tick_hz")))
	for raw: Variant in victims:
		var victim: int = Variants.whole(raw)
		if not _struggling(run, victim):
			continue
		var done: int = Variants.whole(struggle.get(victim, 0)) + 1
		struggle[victim] = done
		if done % interval == 1 or interval == 1:
			run.noise.emit(NoiseTypes.Type.STRUGGLE, run.registry.get_entity(victim).tile(), {"source": victim})
		if done >= needed:
			free_victim(run, victim, "struggle", victim)


func _struggling(run: RunState, victim: int) -> bool:
	if not may_struggle(run, victim):
		return false
	if run.inventory != null and run.inventory.actions.has(victim):
		var a: TimedAction = run.inventory.actions[victim]
		if a.verb != &"feel":
			return false
	if run.ring != null and run.ring.rings.has(victim):
		return false
	var slot: int = _slot_of(run, victim)
	var c: InputBuffer.Consumed = run.input_for(slot) if slot >= 0 else null
	return c != null and (c.record.holds & InputRecord.HOLD_INTERACT) != 0


## Freed: out of the jaws (the wound stays), the struggle forgotten, the trap sprung still.
func free_victim(run: RunState, victim: int, how: String, by: int) -> bool:
	if not is_caught(run, victim):
		return false
	var trap: int = run.holds.caught_in(victim).trap_id
	struggle.erase(victim)
	history.append({"tick": run.tick, "what": "freed", "trap": trap, "victim": victim, "by": by, "how": how})
	Log.info("man-trap %d: miner %d freed (%s)" % [trap, victim, how])
	return run.holds.release_caught(run, victim, CaughtHold.Outcome.FREED)

#endregion

#region Cells

## GEN-10's man-traps of each cell loaded since the last tick, set or (GEN-13's record) sprung.
func _spawn_pending(run: RunState) -> void:
	if _pending.is_empty():
		return
	var cells: Array[Vector2i] = _pending.duplicate()
	_pending.clear()
	cells.sort()
	for cell: Vector2i in cells:
		if run.placed == null or run.mine == null or not run.mine.native.is_loaded(cell):
			continue
		var present: Dictionary = {}
		for raw: Variant in traps.values():
			var t: Trap = raw
			if t.cell == cell and not t.pid.is_empty():
				present[t.pid] = true
		for p: Dictionary in run.placed.of_kind(cell, "man_trap"):
			var pid: String = str(p["id"])
			var tile: Vector2i = p["tile"]
			if not present.has(pid):
				place(run, tile, pid)


func _on_unloading(run: RunState, cell: Vector2i) -> void:
	_pending.erase(cell)
	for raw: Variant in _sorted_ids():
		var t: Trap = traps[raw]
		if t.cell != cell:
			continue
		traps.erase(raw)
		if run.registry.has(t.entity):
			run.registry.destroy(t.entity)


## GEN-13: a sprung trap's record, as its cell commits (or a resume restores the log).
func _replay(run: RunState, _cell: Vector2i, key: String, p: Dictionary, _t: int) -> void:
	if not Variants.flag(p.get("sprung", false)):
		return
	var pid: String = key.trim_prefix(KEY_PREFIX)
	sprung_ids[pid] = true
	for raw: Variant in traps.values():
		var t: Trap = raw
		if t.pid == pid and not t.sprung:
			t.sprung = true
			_show(run, t)


## Its identity record: the jaws set or sprung (seen only as VIS-03 allows).
func _show(run: RunState, t: Trap) -> void:
	if run.replication != null and t.entity != 0:
		run.replication.native.set_entity_held(t.entity, SeenKind.TRAP_SPRUNG if t.sprung else 0)

#endregion


func _sorted_ids() -> Array:
	var ids: Array = traps.keys()
	ids.sort()
	return ids


static func _hand(run: RunState, miner: int) -> bool:
	return run.crew != null and Variants.flag(run.crew.is_hand_driven.call(miner))


static func _slot_of(run: RunState, entity: int) -> int:
	if run.movement == null:
		return -1
	for slot: int in run.movement.miner_slots():
		if run.movement.miner(slot).entity_id == entity:
			return slot
	return -1


func write_state(writer: SimStateWriter) -> void:
	var ids: Array = _sorted_ids()
	writer.put_i64(ids.size())
	for raw: Variant in ids:
		var t: Trap = traps[raw]
		writer.put_i64(t.entity)
		writer.put_i64(1 if t.sprung else 0)
	var victims: Array = struggle.keys()
	victims.sort()
	writer.put_i64(victims.size())
	for raw: Variant in victims:
		writer.put_i64(Variants.whole(raw))
		writer.put_i64(Variants.whole(struggle[raw]))


func save_state() -> Dictionary:
	return {"struggle": struggle.duplicate(), "sprung": sprung_ids.duplicate()}


func load_state(_run: RunState, state: Dictionary) -> void:
	struggle = Variants.dict(state.get("struggle", {})).duplicate()
	for raw: Variant in Variants.dict(state.get("sprung", {})).keys():
		sprung_ids[str(raw)] = true
