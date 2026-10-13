class_name ItemWorld
extends RefCounted
## MNR-04: items lying in the world. Each is an ITEM entity in the registry (a small thing to
## VIS-03: seen only at 0.30, never a token) with its Item record. Every move, take, set-down and
## spend is logged for GEN-13's diff log (`changes`, until that ticket takes it over).
## Server-only.

## entity -> Item
var items: Dictionary = {}
## GEN-13's entries: {tick, op, uid, kind, count, entity, tile, miner}.
var changes: Array[Dictionary] = []
var _next_uid: int = 1


func new_uid() -> int:
	_next_uid += 1
	return _next_uid - 1


## A new item of a kind (placement, GEN-10; tests).
func make(kind: ItemKinds.Kind, count: int = 1, state: Dictionary = {}) -> Item:
	return Item.make(new_uid(), kind, count, state)


## Lays an item on the floor at `at` and returns its entity.
func put(run: RunState, item: Item, at: Vector2, op: StringName = &"put", miner: int = 0) -> int:
	var e: int = run.registry.create(WorldIds.EntityKind.ITEM, at).id
	items[e] = item
	_log(run, op, item, e, Vector2i(floori(at.x), floori(at.y)), miner)
	return e


## Takes the item off the floor; its entity is gone (null if it is not an item).
func lift(run: RunState, entity: int, op: StringName = &"take", miner: int = 0) -> Item:
	if not items.has(entity):
		return null
	var item: Item = items[entity]
	var tile: Vector2i = run.registry.get_entity(entity).tile()
	items.erase(entity)
	run.registry.destroy(entity)
	_log(run, op, item, entity, tile, miner)
	return item


## An entity created elsewhere (the first lamp, LFT-01) becomes an item record.
func adopt(run: RunState, entity: int, item: Item) -> void:
	items[entity] = item
	_log(run, &"put", item, entity, run.registry.get_entity(entity).tile(), 0)


func item_at(entity: int) -> Item:
	return items.get(entity, null)


## Logs a change that happens in a miner's hands (spent, swapped, moved by a flip).
func note(run: RunState, op: StringName, item: Item, miner: int) -> void:
	_log(run, op, item, 0, Vector2i.ZERO, miner)


func _log(run: RunState, op: StringName, item: Item, entity: int, tile: Vector2i, miner: int) -> void:
	changes.append({"tick": run.tick, "op": op, "uid": item.uid, "kind": item.kind, "count": item.count,
		"entity": entity, "tile": tile, "miner": miner})


func write_state(writer: SimStateWriter) -> void:
	var ids: Array = items.keys()
	ids.sort()
	writer.put_i64(ids.size())
	for raw: Variant in ids:
		var it: Item = items[raw]
		writer.put_i64(int(Variants.number(raw)))
		writer.put_i64(it.uid)
		writer.put_i64(it.kind)
		writer.put_i64(it.count)
