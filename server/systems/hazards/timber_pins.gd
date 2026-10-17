class_name TimberPins
extends SimSystem
## HAZ-03 (Gameplay §8.2, §11.3, §4.6, A.5): freeing a miner Caught under a timber pin, the prop a
## roof fall drops on anyone within hazards.collapse_pin_edge_tiles of its edge (CollapsePoints).
## - **The crowbar** (on the rescuer's belt): the ring's "Lever the prop off", held for
##   traps.timber_pin_free_crowbar_s.
## - **Two miners** both holding interact beside the victim: the ring's "Lift the prop", for
##   traps.timber_pin_free_pair_s. The first to hold waits for the second, whose press starts it;
##   either letting go, or leaving the victim's touch range, cancels it with nothing done. A Hired
##   Hand POINTed to free the victim holds as the second miner, never the first (MOD-08, Proposed).
## - **Alone:** the victim holds interact to struggle, traps.timber_pin_struggle_s of holding in
##   all, a struggle (noise.struggle_np) every noise.struggle_interval_s while holding; pausing
##   keeps the progress.
## Freed, the miner is Hurt (MinerStateSystem's release of a timber pin) and TrapEvents says so. A
## Stythe's drag tears a pinned miner out with no wound (RSC-03). An unconscious miner stays pinned
## until freed, and never struggles. Server-only.

## victim -> ticks of struggle held so far.
var struggle: Dictionary = {}
## Every freeing: {tick, victim, how ("crowbar", "pair", "struggle"), by}.
var history: Array[Dictionary] = []


func stage() -> int:
	return StageTable.Stage.WORLD


func order() -> int:
	return 62


func system_name() -> String:
	return "timber_pins"


## Hashed while a struggle is under way, so a run with none hashes as before.
func hashed() -> bool:
	return not struggle.is_empty()


func bind(run: RunState) -> void:
	if run.holds != null:
		run.holds.caught_ended.connect(func(_trap: int, _outcome: CaughtHold.Outcome, victim: int) -> void: struggle.erase(victim))
	if run.ring == null:
		return
	var pinned_states: Array[int] = [MinerTransitions.Life.CAUGHT, MinerTransitions.Life.UNCONSCIOUS]
	run.ring.registry.register("lever_prop", pinned_states,
		func(r: RunState, actor: int, target: int) -> bool:
			return _may_free(r, actor, target) and r.tools_parts != null and r.tools_parts.has_tool(r, [actor], ItemKinds.Kind.CROWBAR),
		func(r: RunState, actor: int, target: int) -> TimedAction: return _lever(r, actor, target))
	run.ring.registry.register("lift_prop", pinned_states,
		func(r: RunState, actor: int, target: int) -> bool: return _may_free(r, actor, target),
		func(r: RunState, actor: int, target: int) -> TimedAction: return _lift(r, actor, target))


static func is_pinned(run: RunState, victim: int) -> bool:
	if run.holds == null:
		return false
	var h: CaughtHold = run.holds.caught_in(victim)
	return h != null and h.kind == CaughtHold.Kind.TIMBER_PIN


## A rescuer: another miner, conscious and standing, never a Hired Hand (Hands never use tools, and
## join a lift only as its second miner).
static func _may_free(run: RunState, actor: int, target: int) -> bool:
	if actor == target or not is_pinned(run, target) or _hand(run, actor):
		return false
	return run.miner_state == null or run.miner_state.miner(actor) == null or run.miner_state.life(actor) == MinerTransitions.Life.UPRIGHT


## Whether the miner may struggle free (StatusWire's key hint): pinned, conscious, a player's own.
static func may_struggle(run: RunState, miner: int) -> bool:
	return is_pinned(run, miner) and not _hand(run, miner) and run.miner_state != null \
		and run.miner_state.life(miner) == MinerTransitions.Life.CAUGHT


static func _hand(run: RunState, miner: int) -> bool:
	return run.crew != null and Variants.flag(run.crew.is_hand_driven.call(miner))


func _lever(run: RunState, actor: int, target: int) -> TimedAction:
	var a: TimedAction = TimedAction.make(actor, &"lever_prop", Tuning.f(&"traps.timber_pin_free_crowbar_s"), InputRecord.HOLD_INTERACT)
	a.target_entity = target
	a.reach = Tuning.f(&"vision.touch_range_tiles")
	a.valid = func() -> bool: return is_pinned(run, target) and run.tools_parts.has_tool(run, [actor], ItemKinds.Kind.CROWBAR)
	a.effect = func() -> void: free_victim(run, target, "crowbar", actor)
	return a


## The lift starts only with a second miner already holding interact beside the victim; it runs as
## long as both hold and stay in the victim's touch range.
func _lift(run: RunState, actor: int, target: int) -> TimedAction:
	if _lift_under_way(run, target):
		return null
	var partner: int = second_miner(run, actor, target)
	if partner == 0:
		return null
	var a: TimedAction = TimedAction.make(actor, &"lift_prop", Tuning.f(&"traps.timber_pin_free_pair_s"), InputRecord.HOLD_INTERACT)
	a.target_entity = target
	a.reach = Tuning.f(&"vision.touch_range_tiles")
	a.valid = func() -> bool:
		if not is_pinned(run, target) or not _holding_beside(run, partner, target):
			a.let_go = partner
			return false
		return true
	a.effect = func() -> void: free_victim(run, target, "pair", actor)
	return a


func _lift_under_way(run: RunState, target: int) -> bool:
	if run.inventory == null:
		return false
	for raw: Variant in run.inventory.actions.keys():
		var a: TimedAction = run.inventory.actions[raw]
		if a.verb == &"lift_prop" and a.target_entity == target:
			return true
	return false


## The second miner for a lift: the first (by entity id) other than the actor and the victim who is
## standing, holding interact in the victim's touch range and doing nothing else. 0 when there is none.
static func second_miner(run: RunState, actor: int, target: int) -> int:
	if run.movement == null:
		return 0
	var ids: Array[int] = []
	for slot: int in run.movement.miner_slots():
		ids.append(run.movement.miner(slot).entity_id)
	ids.sort()
	for m: int in ids:
		if m == actor or m == target or (run.inventory != null and run.inventory.actions.has(m)):
			continue
		if _holding_beside(run, m, target):
			return m
	return 0


static func _holding_beside(run: RunState, miner: int, target: int) -> bool:
	if not run.registry.has(miner) or not run.registry.has(target):
		return false
	if run.miner_state != null and run.miner_state.miner(miner) != null and run.miner_state.life(miner) != MinerTransitions.Life.UPRIGHT:
		return false
	var reach: float = Tuning.f(&"vision.touch_range_tiles") + Tuning.f(&"items.range_tolerance")
	if run.registry.get_entity(miner).position.distance_to(run.registry.get_entity(target).position) > reach:
		return false
	var slot: int = _slot_of(run, miner)
	var c: InputBuffer.Consumed = run.input_for(slot) if slot >= 0 else null
	return c != null and (c.record.holds & InputRecord.HOLD_INTERACT) != 0


static func _slot_of(run: RunState, entity: int) -> int:
	if run.movement == null:
		return -1
	for slot: int in run.movement.miner_slots():
		if run.movement.miner(slot).entity_id == entity:
			return slot
	return -1


## The lone struggle: each tick a conscious pinned miner holds interact (with no action of their own
## but feeling, VIS-07's hold with nothing in reach; no ring open; nobody's lift to hold for), a tick
## of progress.
func tick(run: RunState) -> void:
	if run.holds == null:
		return
	var victims: Array = run.holds.caught.keys()
	victims.sort()
	var interval: int = maxi(1, roundi(Tuning.f(&"noise.struggle_interval_s") * Tuning.f(&"net.tick_hz")))
	var needed: int = maxi(1, roundi(Tuning.f(&"traps.timber_pin_struggle_s") * Tuning.f(&"net.tick_hz")))
	for raw: Variant in victims:
		var victim: int = int(Variants.number(raw))
		if not _struggling(run, victim):
			continue
		var done: int = int(Variants.number(struggle.get(victim, 0))) + 1
		struggle[victim] = done
		if done % interval == 1 or interval == 1:
			run.noise.emit(NoiseTypes.Type.STRUGGLE, run.registry.get_entity(victim).tile(), {"source": victim})
		if done >= needed:
			free_victim(run, victim, "struggle", victim)


func _struggling(run: RunState, victim: int) -> bool:
	if not is_pinned(run, victim) or _hand(run, victim) or run.miner_state == null or run.miner_state.life(victim) != MinerTransitions.Life.CAUGHT:
		return false
	if run.inventory != null:
		if run.inventory.is_partner(victim):
			return false
		if run.inventory.actions.has(victim):
			var a: TimedAction = run.inventory.actions[victim]
			if a.verb != &"feel":
				return false
	if run.ring != null and run.ring.rings.has(victim):
		return false
	var slot: int = _slot_of(run, victim)
	var c: InputBuffer.Consumed = run.input_for(slot) if slot >= 0 else null
	return c != null and (c.record.holds & InputRecord.HOLD_INTERACT) != 0


## Freed: out of the pin (Hurt), the struggle forgotten.
func free_victim(run: RunState, victim: int, how: String, by: int) -> bool:
	if not is_pinned(run, victim):
		return false
	struggle.erase(victim)
	history.append({"tick": run.tick, "victim": victim, "how": how, "by": by})
	Log.info("timber pin: miner %d freed (%s)" % [victim, how])
	return run.holds.release_caught(run, victim, CaughtHold.Outcome.FREED)


func write_state(writer: SimStateWriter) -> void:
	var ids: Array = struggle.keys()
	ids.sort()
	writer.put_i64(ids.size())
	for raw: Variant in ids:
		writer.put_i64(int(Variants.number(raw)))
		writer.put_i64(int(Variants.number(struggle[raw])))


func save_state() -> Dictionary:
	return {"struggle": struggle.duplicate()}


func load_state(_run: RunState, state: Dictionary) -> void:
	struggle = Variants.dict(state.get("struggle", {})).duplicate()
