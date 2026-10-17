class_name HandJobs
extends RefCounted
## MOD-08 (Gameplay §13.9, §11.4, §8.2, §4.3): POINT's jobs. A Hand POINTed at a lit spot takes the
## job whose target lies on it (or beside it), by priority: a caught miner to free, a body to carry
## (MNR-13's fireman's carry), a stretcher or drum-gear end (MNR-14), a paraffin can. It walks there,
## does it with the same timed actions players use, and resumes following with what it carries;
## STOP sets a load down where it stands, and a POINT while carrying a body sets it down at the lit
## spot, on a medbay table when one is free there (MNR-13). It picks up nothing else, ever.

enum Kind { NONE = 0, FREE = 1, BODY = 2, LOAD = 3, CAN = 4, SET_DOWN = 5 }
enum Phase { GO = 0, ACT = 1, CARRY = 2 }

## How far from the lit spot a target may lie (tiles; Proposed: on the spot or beside it).
const SPOT_REACH: float = 1.5
## How close the Hand stands to work its target (tiles; inside MNR-05's touch range).
const WORK_REACH: float = 0.8


## The job at `tile`: {kind, target, tile} or {} for none. `hand` never picks itself.
static func pick(run: RunState, hand: int, tile: Vector2i) -> Dictionary:
	var spot: Vector2 = Vector2(tile) + Vector2(0.5, 0.5)
	if run.holds != null:
		var victims: Array = run.holds.caught.keys()
		victims.sort()
		for raw: Variant in victims:
			var v: int = int(Variants.number(raw))
			if v != hand and _near(run, v, spot):
				return {"kind": Kind.FREE, "target": v, "tile": tile}
	if run.miner_state != null and run.carry != null:
		for id: int in run.registry.ids():
			var e: SimEntity = run.registry.get_entity(id)
			if e.kind != WorldIds.EntityKind.MINER or id == hand or run.miner_state.miner(id) == null:
				continue
			if run.miner_state.life(id) >= MinerTransitions.Life.UNCONSCIOUS and run.carry.carrier_of(id) == 0 \
					and e.position.distance_to(spot) <= SPOT_REACH:
				return {"kind": Kind.BODY, "target": id, "tile": tile}
	if run.loads != null:
		var lying: Array[int] = run.loads.lying(run, spot, SPOT_REACH)
		lying.sort()
		for load_entity: int in lying:
			if run.loads.may_take(run, hand, load_entity):
				return {"kind": Kind.LOAD, "target": load_entity, "tile": tile}
	if run.inventory != null:
		for id: int in run.registry.ids():
			var e: SimEntity = run.registry.get_entity(id)
			if e.kind != WorldIds.EntityKind.ITEM or e.position.distance_to(spot) > SPOT_REACH:
				continue
			var it: Item = run.inventory.world.item_at(id)
			if it != null and it.kind == ItemKinds.Kind.PARAFFIN_CAN:
				return {"kind": Kind.CAN, "target": id, "tile": tile}
	return {}


static func _near(run: RunState, entity: int, spot: Vector2) -> bool:
	var e: SimEntity = run.registry.get_entity(entity)
	return e != null and e.position.distance_to(spot) <= SPOT_REACH


## Where the Hand walks for its job: the target's position, a load's nearer free end (MNR-14 takes
## it there), or the lit spot for a set-down.
static func goal_of(run: RunState, hand: int, job: Dictionary) -> Vector2:
	var kind: int = int(Variants.number(job["kind"]))
	var target: int = int(Variants.number(job["target"]))
	if kind == Kind.SET_DOWN:
		var t: Vector2i = job["tile"]
		return Vector2(t) + Vector2(0.5, 0.5)
	if kind == Kind.LOAD and run.loads != null:
		var it: Item = run.inventory.world.item_at(target)
		var seg: LoadSegment = run.loads.segment_of(run, it.uid) if it != null else null
		if seg != null:
			match run.loads.place_for(run, hand, target):
				LoadCarry.Place.FRONT:
					return seg.front_end()
				LoadCarry.Place.REAR:
					return seg.rear_end()
	var e: SimEntity = run.registry.get_entity(target)
	return e.position if e != null else Vector2(-1, -1)


## Whether the job's target is still there to be worked.
static func still_open(run: RunState, hand: int, job: Dictionary) -> bool:
	var target: int = int(Variants.number(job["target"]))
	match int(Variants.number(job["kind"])):
		Kind.FREE:
			return run.holds != null and run.holds.caught.has(target)
		Kind.BODY:
			return run.carry != null and (run.carry.carrier_of(target) == 0 or run.carry.carrier_of(target) == hand) \
				and run.miner_state.life(target) >= MinerTransitions.Life.UNCONSCIOUS
		Kind.LOAD:
			return run.loads != null and (run.loads.carrying(hand) or run.inventory.actions.has(hand)
				or run.loads.may_take(run, hand, target))
		Kind.CAN:
			return run.inventory != null and (CanCarry.holds_can(run, hand) or run.inventory.world.item_at(target) != null)
		Kind.SET_DOWN:
			return run.carry != null and run.carry.is_carrying(hand)
	return false


## Whether the Hand carries its job's load now (it then follows at the load's pace).
static func carrying(run: RunState, hand: int, job: Dictionary) -> bool:
	match int(Variants.number(job["kind"])):
		Kind.BODY, Kind.SET_DOWN:
			return run.carry != null and run.carry.is_carrying(hand)
		Kind.LOAD:
			return run.loads != null and run.loads.carrying(hand)
		Kind.CAN:
			return CanCarry.holds_can(run, hand)
	return false


## One tick of work beside the target. Returns {interact: bool, done: bool}: the interact held for
## the timed action under way; done once the job is over (freed, set down) or turned to carrying.
static func act(run: RunState, hand: int, job: Dictionary, worked_ticks: int) -> Dictionary:
	var target: int = int(Variants.number(job["target"]))
	match int(Variants.number(job["kind"])):
		Kind.FREE:
			var hold: CaughtHold = run.holds.caught[target]
			# A timber pin takes two (HAZ-03): the Hand only as the second miner beside a human.
			if hold.kind == CaughtHold.Kind.TIMBER_PIN and not _human_beside(run, hand, target):
				return {"interact": false, "done": false}
			if worked_ticks >= roundi(Tuning.f(&"hands.free_s") * Tuning.f(&"net.tick_hz")):
				run.holds.release_caught(run, target, CaughtHold.Outcome.FREED)
				return {"interact": false, "done": true}
			return {"interact": true, "done": false}
		Kind.BODY:
			if run.carry.is_carrying(hand):
				return {"interact": false, "done": true}
			if not run.inventory.actions.has(hand) and run.carry.may_lift(run, hand, target):
				run.inventory.start_action(run, run.carry.lift_action(run, hand, target))
			return {"interact": true, "done": false}
		Kind.LOAD:
			if run.loads.carrying(hand):
				return {"interact": false, "done": true}
			if not run.inventory.actions.has(hand):
				var a: TimedAction = run.loads.take_action(run, hand, target)
				if a != null:
					run.inventory.start_action(run, a)
			return {"interact": true, "done": false}
		Kind.CAN:
			if not CanCarry.holds_can(run, hand):
				var it: Item = run.inventory.world.lift(run, target, &"take", hand)
				if it != null and not run.inventory.give(run, hand, it):
					run.inventory.world.put(run, it, run.registry.get_entity(hand).position, &"put", hand)
			return {"interact": false, "done": true}
		Kind.SET_DOWN:
			run.carry.set_down(run, hand)
			return {"interact": false, "done": true}
	return {"interact": false, "done": true}


## STOP while carrying: the load is set down where the Hand stands.
static func set_down_here(run: RunState, hand: int) -> void:
	if run.carry != null and run.carry.is_carrying(hand):
		run.carry.set_down(run, hand)
	if run.loads != null and run.loads.carrying(hand):
		run.loads.set_down(run, hand)
	if CanCarry.holds_can(run, hand):
		var h: HandsAndBelt = run.inventory.hands_of(hand)
		var it: Item = h.free_hand
		h.free_hand = null
		run.inventory.world.put(run, it, run.registry.get_entity(hand).position, &"put", hand)
		run.inventory.changed.emit(hand)


static func _human_beside(run: RunState, hand: int, victim: int) -> bool:
	var v: SimEntity = run.registry.get_entity(victim)
	for slot: int in run.movement.miner_slots():
		var m: int = run.movement.miner(slot).entity_id
		if m == hand or m == victim or Variants.flag(run.crew.is_hand_driven.call(m)):
			continue
		if run.miner_state.life(m) == MinerTransitions.Life.UPRIGHT \
				and run.registry.get_entity(m).position.distance_to(v.position) <= SPOT_REACH:
			return true
	return false
