class_name Revival
extends SimSystem
## RSC-02 (Gameplay §11.5): the medbay's revival and the healing kit's cure. Revive is offered only
## on an unconscious miner lying on one of base camp's two tables (never on the floor, never on the
## dead, never in Night Shift, where a kit only cures); Cure on any living miner, yourself included,
## and always offered to a kit-holder so the ring never reveals a mark. One use does one or the
## other. A revived miner rises Upright on a free tile beside the table, belt unchanged, no lamp,
## marks kept, voice back. Hired Hands never use kits. It also hands out the cupboard's kits
## (LFT-01): interact at the cupboard takes one by MNR-04's pick-up (items.pick_up_time); it accepts
## no deposits (Proposed). Stage MINERS, after the ring. Server-only.

signal revived(miner: int, by: int, tick: int)
signal kit_used(user: int, target: int, kind: StringName, mark: StringName)

## HAZ-06 replaces this: cure one sickness on `target` and return the mark cured, or &"" if there
## was nothing to cure (then nothing is spent). M1 has no marks.
var cure: Callable = func(_run: RunState, _target: int) -> StringName: return &""
## Uses completed this run, for telemetry: {tick, user, target, kind, mark}.
var uses: Array[Dictionary] = []


func stage() -> int:
	return StageTable.Stage.MINERS


func order() -> int:
	return 23


func system_name() -> String:
	return "revival"


func bind(run: RunState) -> void:
	if run.inventory != null:
		run.inventory.targets.providers.append(_cupboard_target)
	if run.ring != null:
		var living: Array[int] = [MinerTransitions.Life.UPRIGHT, MinerTransitions.Life.CAUGHT, MinerTransitions.Life.UNCONSCIOUS]
		run.ring.registry.register("cure", living,
			func(r: RunState, actor: int, target: int) -> bool: return KitUse.kit_slot(r, actor) >= 0 and may_cure(r, actor, target),
			func(r: RunState, actor: int, target: int) -> TimedAction: return KitUse.make(r, self, actor, target, KitUse.Mode.CURE))
		run.ring.registry.register("revive", [MinerTransitions.Life.UNCONSCIOUS] as Array[int],
			func(r: RunState, actor: int, target: int) -> bool: return KitUse.kit_slot(r, actor) >= 0 and may_revive(r, actor, target),
			func(r: RunState, actor: int, target: int) -> TimedAction: return KitUse.make(r, self, actor, target, KitUse.Mode.REVIVE))
	if run.inventory != null:
		# A kit's Use from the belt cures yourself.
		run.inventory.use_handlers[ItemKinds.Kind.HEALING_KIT] = func(r: RunState, entity: int, _slot: int) -> void:
			if may_use(r, entity) and may_cure(r, entity, entity):
				r.inventory.start_action(r, KitUse.make(r, self, entity, entity, KitUse.Mode.CURE, InputRecord.HOLD_USE))


## A fresh interact aimed at the cupboard takes a kit.
func tick(run: RunState) -> void:
	if run.movement == null or run.inventory == null or run.base_camp == null:
		return
	for slot: int in run.movement.miner_slots():
		var actor: int = run.movement.miner(slot).entity_id
		var c: InputBuffer.Consumed = run.input_for(slot)
		if c == null or run.inventory.actions.has(actor) or not run.inventory.is_fresh(actor, c.record.holds, InputRecord.HOLD_INTERACT):
			continue
		var t: Dictionary = run.inventory.targets.pick(run, actor, slot, run.inventory.world)
		if t.is_empty() or StringName(str(t["kind"])) != &"cupboard":
			continue
		run.inventory.mark_spent(actor, InputRecord.HOLD_INTERACT)
		run.inventory.start_action(run, take_kit_action(run, actor))


## Taking a kit from the cupboard: MNR-04's pick-up time, held interact, in touch range; refused
## while the free hand is blocked or the belt has no room.
func take_kit_action(run: RunState, actor: int) -> TimedAction:
	var medbay: Medbay = run.base_camp.cupboard()
	var a: TimedAction = TimedAction.make(actor, &"take_kit", Tuning.f(&"items.pick_up_time"), InputRecord.HOLD_INTERACT)
	a.target_point = Vector2(medbay.cupboard) + Vector2(0.5, 0.5)
	a.reach = Tuning.f(&"vision.touch_range_tiles")
	# A probe for the belt check only; the real kit gets its uid when it is taken.
	var probe: Item = Item.make(0, ItemKinds.Kind.HEALING_KIT)
	a.valid = func() -> bool:
		return medbay.kits > 0 and not run.inventory.free_hand_blocked(actor, &"pick_up") and run.inventory.hands_of(actor).fits(probe)
	a.effect = func() -> void:
		if medbay.take_kit():
			run.inventory.give(run, actor, run.inventory.world.make(ItemKinds.Kind.HEALING_KIT))
	return a


func _cupboard_target(run: RunState, _actor: int, at: Vector2, reach: float) -> Array:
	if run.base_camp == null or run.base_camp.cupboard().kits <= 0:
		return []
	var p: Vector2 = Vector2(run.base_camp.cupboard().cupboard) + Vector2(0.5, 0.5)
	return [{"kind": &"cupboard", "id": 0, "point": p}] if p.distance_to(at) <= reach else []


## Hired Hands never use kits (§13.9): refused server-side whoever asks.
func may_use(run: RunState, user: int) -> bool:
	return run.crew == null or not Variants.flag(run.crew.is_hand_driven.call(user))


## A cure on anyone living, yourself included, conscious or not, anywhere.
func may_cure(run: RunState, user: int, target: int) -> bool:
	if not may_use(run, user) or run.miner_state == null or run.miner_state.miner(target) == null:
		return false
	return run.miner_state.life(target) != MinerTransitions.Life.DEAD and run.miner_state.life(target) != MinerTransitions.Life.GRABBED


## A revive: only an unconscious miner lying on a medbay table, never in Night Shift.
func may_revive(run: RunState, user: int, target: int) -> bool:
	if not may_use(run, user) or user == target or run.header.mode == ServerConfig.Mode.NIGHTSHIFT:
		return false
	if run.miner_state == null or run.miner_state.miner(target) == null or run.miner_state.life(target) != MinerTransitions.Life.UNCONSCIOUS:
		return false
	var b: BodyState = run.falls.body_of(target) if run.falls != null else null
	return b != null and b.on_table and b.carried_by == 0 and run.base_camp != null and table_of(run, target).x >= 0


## The table a body lies on, or (-1, -1).
func table_of(run: RunState, body: int) -> Vector2i:
	if run.base_camp == null:
		return Vector2i(-1, -1)
	var medbay: Medbay = run.base_camp.cupboard()
	for t: Vector2i in medbay.tables:
		if int(Variants.number(medbay.bodies.get(t, 0))) == body:
			return t
	return Vector2i(-1, -1)


func complete_cure(run: RunState, user: int, target: int) -> void:
	var mark: StringName = cure.call(run, target)
	if mark == &"":
		return
	_spend(run, user)
	_record(run, user, target, &"cure", mark)


func complete_revive(run: RunState, user: int, target: int) -> void:
	var table: Vector2i = table_of(run, target)
	_spend(run, user)
	run.base_camp.cupboard().take_off(target)
	var b: BodyState = run.falls.body_of(target)
	if b != null:
		b.on_table = false
	var stand: Vector2i = _beside(run, table, target)
	if run.movement != null:
		run.movement.place(run, target, Vector2(stand) + Vector2(0.5, 0.5))
	run.miner_state.revive(target, &"kit")
	revived.emit(target, user, run.tick)
	_record(run, user, target, &"revive", &"")


func _spend(run: RunState, user: int) -> void:
	var slot: int = KitUse.kit_slot(run, user)
	var h: HandsAndBelt = run.inventory.hands_of(user)
	var kit: Item = h.slots[slot]
	kit.count -= 1
	if kit.count <= 0:
		h.slots[slot] = null
	run.inventory.changed.emit(user)


## A free walkable tile beside the table (no other miner on it), sides before corners (Proposed).
func _beside(run: RunState, table: Vector2i, rising: int) -> Vector2i:
	var taken: Dictionary = {}
	for raw: Variant in run.registry.ids():
		var e: SimEntity = run.registry.get_entity(int(Variants.number(raw)))
		if e.kind == WorldIds.EntityKind.MINER and e.id != rising:
			taken[e.tile()] = true
	for d: Vector2i in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0),
			Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var t: Vector2i = table + d
		if run.mine != null and run.mine.native.is_walkable(t) and not taken.has(t):
			return t
	return table


func _record(run: RunState, user: int, target: int, kind: StringName, mark: StringName) -> void:
	uses.append({"tick": run.tick, "user": user, "target": target, "kind": str(kind), "mark": str(mark)})
	kit_used.emit(user, target, kind, mark)
	var e: SimEntity = run.registry.get_entity(user)
	Log.info("telemetry kit_used kind=%s mark=%s on_self=%s ring=%d" % [kind, mark if mark != &"" else "none",
		str(user == target).to_lower(), Depth.ring_for_miner(run, user) if e != null else 0])


## Proposed kit-starvation proxy for run end (GDD §15.12): some miner lay unconscious on a table and
## was never revived.
func starved(run: RunState) -> bool:
	if run.base_camp == null:
		return false
	for raw: Variant in run.base_camp.cupboard().bodies.values():
		var body: int = int(Variants.number(raw))
		if body != 0 and run.miner_state != null and run.miner_state.miner(body) != null \
				and run.miner_state.life(body) == MinerTransitions.Life.UNCONSCIOUS:
			return true
	return false
