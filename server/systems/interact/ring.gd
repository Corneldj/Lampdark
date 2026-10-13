class_name RingSystem
extends SimSystem
## MNR-05 (stage MINERS, after the inventory and before feeling): the interact ring (Gameplay §4.3).
## A tap of interact on a teammate in touch range, seen with identity or just felt (never a fringe
## token), opens the ring after a range check rewound to what the actor's client showed (NET-06).
## The server builds the options from the target's visible state and what the actor carries
## (RingOptions) and sends them to the actor alone; a RING_CHOICE action picks one; holding interact
## performs it (releasing cancels, nothing spent); leaving touch range closes the ring. Nothing any
## option does lets anyone but a lamp's holder open it, raise its wick or lower its oil, except a
## completed share (MNR-07), which needs both holding. Server-only, but the actor's own RING messages.

signal opened(actor: int, target: int)
signal closed(actor: int, reason: String)

var registry: RingOptions = RingOptions.new()
## actor -> {target, options: Array[String], chosen: int, sent: PackedByteArray}
var rings: Dictionary = {}
## [slot, bytes] for Replication to send to that client only.
var outbox: Array[Array] = []


func stage() -> int:
	return StageTable.Stage.MINERS


func order() -> int:
	return 22


func system_name() -> String:
	return "ring"


func bind(run: RunState) -> void:
	_register_builtin()
	if run.inventory != null:
		run.inventory.targets.providers.append(_teammate_targets)
	# A felt standing teammate opens the ring; a felt body is still lifted (VIS-07, RSC-01).
	if run.feel != null:
		var lift: Callable = run.feel.felt_uses.get(WorldIds.EntityKind.MINER, Callable())
		var use: Callable = func(r: RunState, miner: int, entity: int) -> bool:
			if r.falls != null and r.falls.body_of(entity) != null:
				return lift.is_valid() and Variants.flag(lift.call(r, miner, entity))
			return open(r, miner, entity)
		run.feel.register_felt_use(WorldIds.EntityKind.MINER, use)


## Opens the ring on `target`; false if out of touch range (rewound) or the actor may not use it.
func open(run: RunState, actor: int, target: int, shown_tick: int = -1) -> bool:
	if not run.registry.has(actor) or not run.registry.has(target) or actor == target:
		return false
	if run.crew != null and Variants.flag(run.crew.is_hand_driven.call(actor)):
		return false
	if run.miner_state != null and run.miner_state.miner(actor) != null:
		var interact: String = str(run.miner_state.capabilities(actor)["interact"])
		if interact != "yes" and interact != "reach":
			return false
	var reach: float = Tuning.f(&"vision.touch_range_tiles")
	var near: bool = run.registry.get_entity(actor).position.distance_to(run.registry.get_entity(target).position) <= reach
	if not near and run.rewind != null and shown_tick >= 0:
		near = run.rewind.in_range_at(actor, target, reach, shown_tick)
	if not near:
		return false
	rings[actor] = {"target": target, "options": registry.offered(run, actor, target), "chosen": -1, "sent": PackedByteArray()}
	opened.emit(actor, target)
	_send(run, actor)
	return true


func close(run: RunState, actor: int, reason: String) -> void:
	if not rings.has(actor):
		return
	rings.erase(actor)
	var slot: int = _slot_of(run, actor)
	if slot >= 0:
		outbox.append([slot, RingMessages.encode(false, [] as Array[String], -1, [])])
	closed.emit(actor, reason)


## Picks an option by its index in the list the actor was sent.
func choose(run: RunState, actor: int, index: int) -> bool:
	var r: Dictionary = rings.get(actor, {})
	var options: Array[String] = r.get("options", [] as Array[String])
	if r.is_empty() or index < 0 or index >= options.size():
		return false
	r["chosen"] = index
	_send(run, actor)
	return true


## The chosen option's action, started now (holding interact performs it).
func perform(run: RunState, actor: int) -> TimedAction:
	var r: Dictionary = rings.get(actor, {})
	if r.is_empty() or int(Variants.number(r["chosen"])) < 0:
		return null
	var options: Array[String] = r["options"]
	var id: String = options[int(Variants.number(r["chosen"]))]
	var target: int = int(Variants.number(r["target"]))
	var o: RingOptions.Option = registry.options[id]
	if o.actor_check.is_valid() and not Variants.flag(o.actor_check.call(run, actor, target)):
		return null
	var a: TimedAction = o.make.call(run, actor, target)
	if a == null:
		return null
	if o.both:
		BothHold.join(a, [actor, target] as Array[int])
	a.completed.connect(func(_x: TimedAction) -> void: close(run, actor, "done"))
	if not run.inventory.start_action(run, a):
		return null
	return a


func tick(run: RunState) -> void:
	if run.movement == null or run.inventory == null:
		return
	var by_entity: Dictionary = {}
	for slot: int in run.movement.miner_slots():
		by_entity[run.movement.miner(slot).entity_id] = slot
	var miners: Array = by_entity.keys()
	miners.sort()
	for raw: Variant in miners:
		var actor: int = int(Variants.number(raw))
		var slot: int = int(Variants.number(by_entity[raw]))
		var c: InputBuffer.Consumed = run.input_for(slot)
		if c == null or run.inventory.is_partner(actor):
			continue
		for act: ActionRecord in c.actions:
			if act.kind == ActionRecord.Kind.RING_CHOICE:
				choose(run, actor, act.arg)
		if rings.has(actor):
			_follow(run, actor, slot, c)
		elif not run.inventory.actions.has(actor) and run.inventory.is_fresh(actor, c.record.holds, InputRecord.HOLD_INTERACT):
			var t: Dictionary = run.inventory.targets.pick(run, actor, slot, run.inventory.world)
			if not t.is_empty() and StringName(str(t["kind"])) == &"miner":
				run.inventory.mark_spent(actor, InputRecord.HOLD_INTERACT)
				open(run, actor, int(Variants.number(t["id"])), c.shown_tick)


## An open ring: closed when the target leaves touch range (or is gone), refreshed when what is
## offered changes, and a fresh interact hold performs the chosen option.
func _follow(run: RunState, actor: int, _slot: int, c: InputBuffer.Consumed) -> void:
	var r: Dictionary = rings[actor]
	var target: int = int(Variants.number(r["target"]))
	var reach: float = Tuning.f(&"vision.touch_range_tiles") + Tuning.f(&"items.range_tolerance")
	if not run.registry.has(target) or run.registry.get_entity(target).position.distance_to(run.registry.get_entity(actor).position) > reach:
		close(run, actor, "out of reach")
		return
	if not run.inventory.actions.has(actor):
		var now: Array[String] = registry.offered(run, actor, target)
		var was: Array[String] = r["options"]
		if now != was:
			var chosen_id: String = was[int(Variants.number(r["chosen"]))] if int(Variants.number(r["chosen"])) >= 0 else ""
			r["options"] = now
			r["chosen"] = now.find(chosen_id) if not chosen_id.is_empty() else -1
			_send(run, actor)
		if int(Variants.number(r["chosen"])) >= 0 and run.inventory.is_fresh(actor, c.record.holds, InputRecord.HOLD_INTERACT):
			run.inventory.mark_spent(actor, InputRecord.HOLD_INTERACT)
			perform(run, actor)


## MNR-04's interaction targets: teammates in touch range the actor sees with identity or just felt.
func _teammate_targets(run: RunState, actor: int, at: Vector2, reach: float) -> Array:
	var out: Array = []
	var slot: int = _slot_of(run, actor)
	var seen: Dictionary = {}
	if run.vision != null and slot >= 0:
		var identified: PackedInt64Array = run.vision.frame_for(slot).get("identified", PackedInt64Array())
		for id: int in identified:
			seen[id] = true
	var felt: int = run.feel.felt_target(run, actor) if run.feel != null else 0
	# A felt body is lifted by interacting again (§5.5, VIS-07); only a felt standing teammate opens the ring.
	if felt != 0 and run.falls != null and run.falls.body_of(felt) != null:
		felt = 0
	var ids: Array = Array(run.registry.ids())
	ids.sort()
	for raw: Variant in ids:
		var id: int = int(Variants.number(raw))
		var e: SimEntity = run.registry.get_entity(id)
		if id == actor or e.kind != WorldIds.EntityKind.MINER or (not seen.has(id) and id != felt):
			continue
		if e.position.distance_to(at) <= reach:
			out.append({"kind": &"miner", "id": id, "point": e.position})
	return out


func _send(run: RunState, actor: int) -> void:
	var r: Dictionary = rings.get(actor, {})
	var slot: int = _slot_of(run, actor)
	if r.is_empty() or slot < 0:
		return
	var target: int = int(Variants.number(r["target"]))
	var belt: Array = []
	if run.falls != null and run.falls.body_of(target) != null:
		for it: Item in run.inventory.hands_of(target).slots:
			belt.append([it.kind, it.count] if it != null else [0, 0])
	var options: Array[String] = r["options"]
	var bytes: PackedByteArray = RingMessages.encode(true, options, int(Variants.number(r["chosen"])), belt)
	if bytes != r["sent"]:
		r["sent"] = bytes
		outbox.append([slot, bytes])


func _slot_of(run: RunState, entity: int) -> int:
	if run.movement == null:
		return -1
	for slot: int in run.movement.miner_slots():
		if run.movement.miner(slot).entity_id == entity:
			return slot
	return -1


## Hand over, take, douse, share oil, pass a flame and lift (their owners' actions).
func _register_builtin() -> void:
	var standing: Array[int] = [MinerTransitions.Life.UPRIGHT, MinerTransitions.Life.CAUGHT]
	var down: Array[int] = [MinerTransitions.Life.UNCONSCIOUS, MinerTransitions.Life.DEAD]
	var can_hand: Callable = func(run: RunState, actor: int, target: int) -> bool:
		var item: Item = _hand_over_item(run, actor)
		return item != null and _receiver_room(run, target, item)
	registry.register("hand_over", standing, can_hand, _hand_over_action)
	var can_douse: Callable = func(run: RunState, _actor: int, target: int) -> bool:
		var l: GauzeLamp = run.lamps.lamp_in_hand(target) if run.lamps != null else null
		return l != null and l.allows(&"douse")
	var douse: Callable = func(run: RunState, actor: int, target: int) -> TimedAction: return run.lamps.douse_action(run, actor, target)
	registry.register("douse", standing, can_douse, douse)
	var can_share: Callable = func(run: RunState, actor: int, target: int) -> bool:
		return run.lamps != null and run.lamps.lamp_in_hand(actor) != null and run.lamps.lamp_in_hand(target) != null
	var share: Callable = func(run: RunState, actor: int, target: int) -> TimedAction: return LampOil.share_action(run, actor, target)
	registry.register("share_oil", standing, can_share, share, true)
	var can_pass: Callable = func(run: RunState, actor: int, target: int) -> bool: return not _flame_pair(run, actor, target).is_empty()
	var pass_flame: Callable = func(run: RunState, actor: int, target: int) -> TimedAction:
		var pair: Array[int] = _flame_pair(run, actor, target)
		return Relight.pass_flame_action(run, pair[0], pair[1])
	registry.register("pass_flame", standing, can_pass, pass_flame, true)
	var can_lift: Callable = func(run: RunState, actor: int, target: int) -> bool:
		if run.carry != null:
			return run.carry.may_lift(run, actor, target)
		return run.falls != null and run.falls.body_of(target) != null and run.inventory.hands_of(actor).free_hand == null
	var lift: Callable = func(run: RunState, actor: int, target: int) -> TimedAction: return run.falls.lift_action(run, actor, target)
	registry.register("lift", down, can_lift, lift)
	for i: int in Tuning.i(&"items.belt_slots"):
		var slot: int = i
		var can_take: Callable = func(run: RunState, actor: int, target: int) -> bool:
			var it: Item = run.inventory.hands_of(target).slots[slot]
			return it != null and run.inventory.hands_of(actor).fits(it)
		var take: Callable = func(run: RunState, actor: int, target: int) -> TimedAction: return run.falls.take_item_action(run, actor, target, slot)
		registry.register("take:%d" % slot, down, can_take, take)


## Who gives and who takes a flame: [giver, taker], one burning and the other's lamp Out; else [].
func _flame_pair(run: RunState, actor: int, target: int) -> Array[int]:
	if run.lamps == null:
		return []
	var a: GauzeLamp = run.lamps.lamp_in_hand(actor)
	var b: GauzeLamp = run.lamps.lamp_in_hand(target)
	if a == null or b == null:
		return []
	if a.burning() and Relight.offered(b, Relight.PASSED):
		return [actor, target]
	if b.burning() and Relight.offered(a, Relight.PASSED):
		return [target, actor]
	return []


## What a hand-over gives: the selected belt item, else the lamp in the lamp hand.
func _hand_over_item(run: RunState, actor: int) -> Item:
	var h: HandsAndBelt = run.inventory.hands_of(actor)
	var selected: Item = h.slots[h.selected]
	if selected != null:
		return selected
	return h.lamp_hand if not h.hooked else null


## The receiver has room: a lamp to an empty lamp hand, a can to an empty free hand, else the belt.
func _receiver_room(run: RunState, target: int, item: Item) -> bool:
	var h: HandsAndBelt = run.inventory.hands_of(target)
	if ItemKinds.is_lamp(item.kind):
		return h.lamp_hand == null
	return h.fits(item)


func _hand_over_action(run: RunState, actor: int, target: int) -> TimedAction:
	var item: Item = _hand_over_item(run, actor)
	var giver: HandsAndBelt = run.inventory.hands_of(actor)
	var a: TimedAction = TimedAction.make(actor, &"hand_over", Tuning.f(&"items.hand_over_time"), InputRecord.HOLD_INTERACT)
	a.target_entity = target
	a.reach = Tuning.f(&"vision.touch_range_tiles")
	a.valid = func() -> bool:
		return item != null and (giver.lamp_hand == item or giver.slots.has(item)) and _receiver_room(run, target, item)
	a.effect = func() -> void:
		var receiver: HandsAndBelt = run.inventory.hands_of(target)
		if giver.lamp_hand == item:
			giver.lamp_hand = null
		else:
			giver.slots[giver.slots.find(item)] = null
		if ItemKinds.is_lamp(item.kind):
			# A lamp arrives in the empty lamp hand, burning as it is.
			receiver.lamp_hand = item
		else:
			receiver.store(item)
		run.inventory.world.note(run, &"hand_over", item, target)
		run.inventory.changed.emit(actor)
		run.inventory.changed.emit(target)
	return a


func write_state(writer: SimStateWriter) -> void:
	var ids: Array = rings.keys()
	ids.sort()
	for raw: Variant in ids:
		var r: Dictionary = rings[raw]
		writer.put_i64(int(Variants.number(raw)))
		writer.put_i64(int(Variants.number(r["target"])))
		writer.put_i64(int(Variants.number(r["chosen"])))
