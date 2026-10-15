class_name ItemPlaces
extends RefCounted
## MNR-09: where every item of a kind is now (MNR-04's hands, belt slots and floor), in a fixed
## order (miners by entity id, then the floor by entity id), and taking one out of wherever it is.
## A place: {item, holder (miner entity, 0 on the floor), where (&"lamp", &"free", &"slot" or
## &"floor"), slot (belt index, or -1), entity (the floor item's entity, or 0), position}.
## Server-only.


static func of_kind(run: RunState, kind: ItemKinds.Kind) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if run.inventory == null:
		return out
	var miners: Array = run.inventory.hands.keys()
	miners.sort()
	for raw: Variant in miners:
		var m: int = int(Variants.number(raw))
		var h: HandsAndBelt = run.inventory.hands[raw]
		var me: SimEntity = run.registry.get_entity(m)
		var at: Vector2 = me.position if me != null else Vector2.ZERO
		if h.lamp_hand != null and h.lamp_hand.kind == kind:
			out.append({"item": h.lamp_hand, "holder": m, "where": &"lamp", "slot": -1, "entity": 0, "position": at})
		if h.free_hand != null and h.free_hand.kind == kind:
			out.append({"item": h.free_hand, "holder": m, "where": &"free", "slot": -1, "entity": 0, "position": at})
		for i: int in h.slots.size():
			if h.slots[i] != null and h.slots[i].kind == kind:
				out.append({"item": h.slots[i], "holder": m, "where": &"slot", "slot": i, "entity": 0, "position": at})
	var ids: Array = run.inventory.world.items.keys()
	ids.sort()
	for raw: Variant in ids:
		var it: Item = run.inventory.world.items[raw]
		if it.kind == kind:
			var e: SimEntity = run.registry.get_entity(int(Variants.number(raw)))
			out.append({"item": it, "holder": 0, "where": &"floor", "slot": -1, "entity": int(Variants.number(raw)),
				"position": e.position if e != null else Vector2.ZERO})
	return out


## Takes the item at `place` out of the world (burnt out, spent): logged as `op`.
static func remove(run: RunState, place: Dictionary, op: StringName) -> void:
	var it: Item = place["item"]
	var holder: int = int(Variants.number(place["holder"]))
	match StringName(str(place["where"])):
		&"floor":
			run.inventory.world.lift(run, int(Variants.number(place["entity"])), op)
			return
		&"lamp":
			var h: HandsAndBelt = run.inventory.hands_of(holder)
			if h.lamp_hand == it:
				h.lamp_hand = null
		&"free":
			var h: HandsAndBelt = run.inventory.hands_of(holder)
			if h.free_hand == it:
				h.free_hand = null
		&"slot":
			var h: HandsAndBelt = run.inventory.hands_of(holder)
			var i: int = int(Variants.number(place["slot"]))
			if h.slots[i] == it:
				h.slots[i] = null
	run.inventory.world.note(run, op, it, holder)
	run.inventory.changed.emit(holder)


## Lays a held item down burning where its holder is (a flare dropped by a falling or grabbed miner).
static func drop_at_holder(run: RunState, place: Dictionary, op: StringName) -> int:
	var it: Item = place["item"]
	var holder: int = int(Variants.number(place["holder"]))
	var h: HandsAndBelt = run.inventory.hands_of(holder)
	if h.free_hand == it:
		h.free_hand = null
	elif h.lamp_hand == it:
		h.lamp_hand = null
	else:
		return 0
	run.inventory.changed.emit(holder)
	var me: SimEntity = run.registry.get_entity(holder)
	var at: Vector2 = place["position"]
	return run.inventory.world.put(run, it, me.position if me != null else at, op, holder)
