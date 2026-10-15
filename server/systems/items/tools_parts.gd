class_name ToolsParts
extends SimSystem
## MNR-12 (stage MINERS, after the stones): tools and parts (Gameplay §4.6, §3.3, §8.2). The four
## tools take a slot each and are never used up; the five parts (fuses 3 a slot, rope clamps 4) are
## found, never made, and used up only when a fit completes. The repair jobs (LFT-04, LFT-05,
## LFT-07) ask through one API: `has_tool`, `tool_holder`, `count_part`, `consume_part` (all or
## nothing) and `fit_action` (spends on completion; a cancelled fit spends nothing). Hired Hands
## never use tools or fit parts: the API refuses them (§13.9).
##
## Any tool springs a known trap on purpose (§8.2): from beside it, not on its tile, hold interact
## traps.spring_with_tool_s with any tool on the belt, the tool kept. "Known" is seen with identity
## (VIS-03) or felt (VIS-07). HAZ-01 and HAZ-02 set `spring_on_purpose` and `trap_is_set`; until
## then a stub records the call. No tool is a weapon: nothing maps one to an action on a creature.
## Server-only.

const TOOLS: Array[ItemKinds.Kind] = [ItemKinds.Kind.SPANNER, ItemKinds.Kind.HAMMER, ItemKinds.Kind.CROWBAR,
	ItemKinds.Kind.WIRE_CUTTERS]
const PARTS: Array[ItemKinds.Kind] = [ItemKinds.Kind.FUSE, ItemKinds.Kind.MAGNETO, ItemKinds.Kind.DRIVE_BELT,
	ItemKinds.Kind.BRAKE_SHOE, ItemKinds.Kind.ROPE_CLAMP]
## §3.3's jobs: the tools each needs and the parts it fits (the drum gear is MNR-14's load).
const JOBS: Dictionary = {
	&"magneto": {"tools": [ItemKinds.Kind.SPANNER], "parts": {ItemKinds.Kind.MAGNETO: 1}},
	&"brake_shoes": {"tools": [ItemKinds.Kind.SPANNER], "parts": {ItemKinds.Kind.BRAKE_SHOE: 2}},
	&"drum_gear": {"tools": [ItemKinds.Kind.SPANNER, ItemKinds.Kind.HAMMER], "parts": {}},
	&"rope_clamps": {"tools": [ItemKinds.Kind.SPANNER], "parts": {ItemKinds.Kind.ROPE_CLAMP: 4}},
	&"drive_belt": {"tools": [ItemKinds.Kind.HAMMER], "parts": {ItemKinds.Kind.DRIVE_BELT: 1}},
	&"free_the_cage": {"tools": [ItemKinds.Kind.CROWBAR], "parts": {}},
	&"power": {"tools": [ItemKinds.Kind.WIRE_CUTTERS], "parts": {ItemKinds.Kind.FUSE: 3}},
}

## HAZ-01, HAZ-02: (run, trap entity, by miner) -> void, the trap snaps or crashes and is spent.
var spring_on_purpose: Callable = func(_r: RunState, trap: int, by: int) -> void:
	stub_springs.append({"trap": trap, "by": by})
## HAZ-01, HAZ-02: (run, trap entity) -> bool, the trap is set (not yet sprung).
var trap_is_set: Callable = func(_r: RunState, _trap: int) -> bool: return true
## The stub's record until the trap tickets land: {trap, by}.
var stub_springs: Array[Dictionary] = []
## Every spring on purpose: {tick, trap, by, tool}.
var springs: Array[Dictionary] = []
## Every part spent: {tick, miner, kind, n}.
var spent: Array[Dictionary] = []


func stage() -> int:
	return StageTable.Stage.MINERS


func order() -> int:
	return 35


func system_name() -> String:
	return "tools_parts"


func bind(run: RunState) -> void:
	if run.inventory != null:
		run.inventory.targets.providers.append(_trap_targets)


static func is_tool_kind(kind: int) -> bool:
	return TOOLS.has(kind)


static func is_part_kind(kind: int) -> bool:
	return PARTS.has(kind)


## A Hired Hand never uses a tool or fits a part (MOD-08's never list).
static func is_hand(run: RunState, miner: int) -> bool:
	return run.crew != null and Variants.flag(run.crew.is_hand_driven.call(miner))


## Whether any of `miners` (not a Hand) has a `kind` tool on the belt.
func has_tool(run: RunState, miners: Array, kind: ItemKinds.Kind) -> bool:
	return tool_holder(run, miners, kind) != 0


## The first of `miners` (in the given order, not a Hand) with a `kind` tool, or 0.
func tool_holder(run: RunState, miners: Array, kind: ItemKinds.Kind) -> int:
	if not is_tool_kind(kind) or run.inventory == null:
		return 0
	for raw: Variant in miners:
		var m: int = int(Variants.number(raw))
		if not is_hand(run, m) and run.inventory.hands.has(m) and run.inventory.hands_of(m).count_of(kind) > 0:
			return m
	return 0


## Any tool on `miner`'s belt (the first of TOOLS held), or NONE; NONE for a Hand.
func any_tool(run: RunState, miner: int) -> ItemKinds.Kind:
	for kind: ItemKinds.Kind in TOOLS:
		if tool_holder(run, [miner], kind) != 0:
			return kind
	return ItemKinds.Kind.NONE


func count_part(run: RunState, miner: int, kind: ItemKinds.Kind) -> int:
	if not is_part_kind(kind) or run.inventory == null or not run.inventory.hands.has(miner):
		return 0
	return run.inventory.hands_of(miner).count_of(kind)


## Removes exactly `n` of a part from `miner`'s belt, or nothing (too few, not a part, a Hand).
func consume_part(run: RunState, miner: int, kind: ItemKinds.Kind, n: int) -> bool:
	if not is_part_kind(kind) or n <= 0 or is_hand(run, miner) or count_part(run, miner, kind) < n:
		return false
	if not run.inventory.consume(run, miner, kind, n):
		return false
	spent.append({"tick": run.tick, "miner": miner, "kind": kind, "n": n})
	return true


## A fit for the jobs: `seconds` held on `bit`, needing `n` of `kind` on `miner`'s belt all along;
## the parts are spent only when it completes, then `on_fitted` runs. Null for a Hand.
func fit_action(run: RunState, miner: int, kind: ItemKinds.Kind, n: int, seconds: float, bit: int, on_fitted: Callable = Callable()) -> TimedAction:
	if is_hand(run, miner) or not is_part_kind(kind):
		return null
	var a: TimedAction = TimedAction.make(miner, &"fit_part", seconds, bit)
	a.valid = func() -> bool: return count_part(run, miner, kind) >= n
	a.effect = func() -> void:
		if consume_part(run, miner, kind, n) and on_fitted.is_valid():
			on_fitted.call()
	return a


## Whether `miner` may spring `trap` now: a set trap they know (identified or felt), in touch
## range but not on its tile, with any tool on the belt, not a Hand.
func can_spring(run: RunState, miner: int, slot: int, trap: int) -> bool:
	var me: SimEntity = run.registry.get_entity(miner)
	var t: SimEntity = run.registry.get_entity(trap)
	if me == null or t == null or t.kind != WorldIds.EntityKind.TRAP or any_tool(run, miner) == ItemKinds.Kind.NONE:
		return false
	if me.tile() == t.tile() or me.position.distance_to(t.position) > Tuning.f(&"vision.touch_range_tiles"):
		return false
	return Variants.flag(trap_is_set.call(run, trap)) and _knows(run, miner, slot, trap)


func tick(run: RunState) -> void:
	if run.movement == null or run.inventory == null:
		return
	for slot: int in run.movement.miner_slots():
		var actor: int = run.movement.miner(slot).entity_id
		var c: InputBuffer.Consumed = run.input_for(slot)
		if c == null or run.inventory.actions.has(actor) or not run.inventory.is_fresh(actor, c.record.holds, InputRecord.HOLD_INTERACT):
			continue
		var t: Dictionary = run.inventory.targets.pick(run, actor, slot, run.inventory.world)
		if t.is_empty() or StringName(str(t["kind"])) != &"spring_trap":
			continue
		run.inventory.mark_spent(actor, InputRecord.HOLD_INTERACT)
		run.inventory.start_action(run, spring_action(run, actor, slot, int(Variants.number(t["id"]))))


## Springing a known trap on purpose: interact held traps.spring_with_tool_s from beside it, any
## tool on the belt all along; the trap snaps or crashes (HAZ-01, HAZ-02), the tool is kept.
func spring_action(run: RunState, actor: int, slot: int, trap: int) -> TimedAction:
	var a: TimedAction = TimedAction.make(actor, &"spring_trap", Tuning.f(&"traps.spring_with_tool_s"), InputRecord.HOLD_INTERACT)
	a.target_entity = trap
	a.reach = Tuning.f(&"vision.touch_range_tiles")
	a.valid = func() -> bool: return can_spring(run, actor, slot, trap)
	a.effect = func() -> void:
		springs.append({"tick": run.tick, "trap": trap, "by": actor, "tool": any_tool(run, actor)})
		spring_on_purpose.call(run, trap, actor)
	return a


func _knows(run: RunState, miner: int, slot: int, trap: int) -> bool:
	if run.feel != null and run.feel.felt_target(run, miner) == trap:
		return true
	if run.vision == null or slot < 0:
		return false
	var identified: PackedInt64Array = run.vision.frame_for(slot).get("identified", PackedInt64Array())
	return identified.has(trap)


## Set traps the actor knows within reach, offered as "spring it" while a tool is on the belt.
func _trap_targets(run: RunState, actor: int, at: Vector2, reach: float) -> Array:
	var out: Array = []
	if any_tool(run, actor) == ItemKinds.Kind.NONE:
		return out
	var slot: int = _slot_of(run, actor)
	for raw: Variant in run.registry.ids():
		var id: int = int(Variants.number(raw))
		var e: SimEntity = run.registry.get_entity(id)
		if e.kind == WorldIds.EntityKind.TRAP and e.position.distance_to(at) <= reach and can_spring(run, actor, slot, id):
			out.append({"kind": &"spring_trap", "id": id, "point": e.position})
	return out


func _slot_of(run: RunState, entity: int) -> int:
	if run.movement == null:
		return -1
	for slot: int in run.movement.miner_slots():
		if run.movement.miner(slot).entity_id == entity:
			return slot
	return -1


func write_state(writer: SimStateWriter) -> void:
	writer.put_i64(springs.size())
	writer.put_i64(spent.size())
