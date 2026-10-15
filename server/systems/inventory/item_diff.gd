class_name ItemDiff
extends RefCounted
## GEN-13 for MNR-04's items (Gameplay §12.6): every item lying in the mine has a record in its
## cell's diff diff, keyed by its ID (GEN-10's placement ID for a generated item, else "u" and its
## run uid): where it lies and all its state (lit, shutter, wick, oil, notches, battery, burn time).
## Taken into a belt or carried to another cell, the old cell's record says taken; the item then
## travels with whoever holds it (their snapshot), so every item is in exactly one place. A cell
## unloading packs its items into their records and lets their entities go; a cell committed again
## puts them back with the same uid, each advanced to the present by its kind's advance function
## (MNR-06's lamps, MNR-09's candles and flares), a burnt-out one gone. Server-only.

var diff: DiffLog = null
## Item ID -> the cell whose record says it lies there.
var cell_of: Dictionary = {}
## ItemKinds.Kind -> (state: Dictionary, at: Vector2, from_tick: int, to_tick: int) -> Variant: the
## state advanced, or null when nothing is left (burnt out). An empty state is a state.
var advances: Dictionary = {}
## uid -> the entity it lies at now (floor items only).
var _entity_of_uid: Dictionary = {}


func bind(run: RunState) -> void:
	diff = run.diff_log
	if diff == null or run.inventory == null:
		return
	run.inventory.world.logged.connect(func(op: StringName, it: Item, entity: int) -> void: _on_logged(run, op, it, entity))
	diff.register(DiffLog.Kind.ITEM, _replay, _advance, _is_default)
	diff.on_evict(_evict)
	diff.on_refresh(_refresh)
	if run.lamps != null:
		run.lamps.lamp_changed.connect(func(l: GauzeLamp, _what: StringName, _cause: String) -> void: _lamp_changed(run, l))


static func id_of(it: Item) -> String:
	return it.placement if not it.placement.is_empty() else "u%d" % it.uid


func _on_logged(run: RunState, op: StringName, it: Item, entity: int) -> void:
	if op == &"replay" or entity == 0:
		return
	var world: ItemWorld = run.inventory.world
	if world.items.get(entity, null) == it:
		_entity_of_uid[it.uid] = entity
		record_floor(run, entity, it)
	else:
		_entity_of_uid.erase(it.uid)
		_left(it)


## The item at `entity` lies on the floor (or a hook): its record, in its cell, is up to date.
func record_floor(run: RunState, entity: int, it: Item) -> void:
	var e: SimEntity = run.registry.get_entity(entity)
	var cell: Vector2i = WorldCoords.cell_of(e.tile())
	var id: String = id_of(it)
	if cell_of.has(id):
		var old: Vector2i = cell_of[id]
		if old != cell:
			diff.taken(old, id)
	cell_of[id] = cell
	diff.record(cell, DiffLog.Kind.ITEM, id, payload(run, it, e.position))


func payload(run: RunState, it: Item, at: Vector2) -> Dictionary:
	# A lamp's oil runs on in GauzeLamp: its item's state is brought up to date first.
	if run.lamps != null and run.lamps.lamps.has(it.uid):
		var live: GauzeLamp = run.lamps.lamps[it.uid]
		run.lamps.mirror(live)
	var p: Dictionary = {"where": "floor", "uid": it.uid, "kind": it.kind, "count": it.count, "state": it.state.duplicate(true),
		"x": at.x, "y": at.y}
	if run.lamps != null and run.lamps.lamps.has(it.uid):
		var l: GauzeLamp = run.lamps.lamps[it.uid]
		p["lamp_phase"] = l.phase
	elif it.state.has("restore_phase"):
		# Replayed, not yet adopted by the lamp system (NET-09 saves at once on a resume): as it was.
		var state: Dictionary = p["state"]
		p["lamp_phase"] = state["restore_phase"]
		state.erase("restore_phase")
	if not it.placement.is_empty():
		p["placement"] = it.placement
	return p


func _left(it: Item) -> void:
	var id: String = id_of(it)
	if cell_of.has(id):
		var old: Vector2i = cell_of[id]
		diff.taken(old, id)
		cell_of.erase(id)


func _lamp_changed(run: RunState, l: GauzeLamp) -> void:
	if l.place != LampRules.Place.FLOOR and l.place != LampRules.Place.HUNG:
		return
	var entity: int = int(Variants.number(_entity_of_uid.get(l.uid, 0)))
	if entity != 0 and run.inventory.world.items.get(entity, null) == l.item:
		record_floor(run, entity, l.item)


## Packs the cell's floor items into their records and lets their entities go (no take logged).
func _evict(run: RunState, cell: Vector2i) -> void:
	var world: ItemWorld = run.inventory.world
	var ids: Array = Array(run.registry.ids_in_cell(cell))
	ids.sort()
	for raw: Variant in ids:
		var entity: int = int(Variants.number(raw))
		if not world.items.has(entity):
			continue
		var it: Item = world.items[entity]
		record_floor(run, entity, it)
		world.items.erase(entity)
		_entity_of_uid.erase(it.uid)
		run.registry.destroy(entity)


## Every floor item in a loaded cell, its record brought up to now.
func _refresh(run: RunState) -> void:
	var world: ItemWorld = run.inventory.world
	var ids: Array = world.items.keys()
	ids.sort()
	for raw: Variant in ids:
		var entity: int = int(Variants.number(raw))
		var it: Item = world.items[raw]
		if run.registry.has(entity):
			record_floor(run, entity, it)


func _advance(p: Dictionary, from_tick: int, to_tick: int) -> Dictionary:
	# Only something alight changes while it lies (a lamp, a candle, a flare); a taken record has
	# no state at all.
	var raw_state: Variant = p.get("state", null)
	if not raw_state is Dictionary or not Variants.flag(Variants.dict(raw_state).get("lit", false)):
		return p
	var kind: int = int(Variants.number(p["kind"]))
	if not advances.has(kind) or to_tick <= from_tick:
		return p
	var at: Vector2 = Vector2(Variants.number(p["x"]), Variants.number(p["y"]))
	# Its values are plain: a shallow copy is a copy.
	var state: Dictionary = Variants.dict(raw_state).duplicate()
	if p.has("lamp_phase"):
		state["lamp_phase"] = p["lamp_phase"]
	var fn: Callable = advances[kind]
	var advanced: Variant = fn.call(state, at, from_tick, to_tick)
	if advanced == null:
		return {}
	var next: Dictionary = advanced
	var out: Dictionary = p.duplicate()
	if next.has("lamp_phase"):
		out["lamp_phase"] = next["lamp_phase"]
		next.erase("lamp_phase")
	out["state"] = next
	return out


func _replay(run: RunState, cell: Vector2i, id: String, p: Dictionary, _tick: int) -> void:
	if str(p.get("where", "")) != "floor":
		return
	var uid: int = int(Variants.number(p["uid"]))
	if _entity_of_uid.has(uid) and run.inventory.world.items.has(_entity_of_uid[uid]):
		return
	# The payload was decoded for this replay alone: its state is the item's own, no copy needed.
	var it: Item = Item.new()
	it.uid = uid
	it.kind = int(Variants.number(p["kind"])) as ItemKinds.Kind
	it.count = int(Variants.number(p["count"]))
	it.state = Variants.dict(p["state"])
	it.placement = str(p.get("placement", ""))
	if p.has("lamp_phase"):
		it.state["restore_phase"] = int(Variants.number(p["lamp_phase"]))
	var at: Vector2 = Vector2(Variants.number(p["x"]), Variants.number(p["y"]))
	var entity: int = run.inventory.world.put(run, it, at, &"replay")
	cell_of[id] = cell
	_entity_of_uid[uid] = entity
	if entity == 0:
		push_error("ItemDiff: replay could not put item %s back" % id)


## A runtime item's taken record: generation never makes it, so its absence is the default.
func _is_default(_cell: Vector2i, id: String, p: Dictionary) -> bool:
	return str(p.get("where", "")) == DiffLog.TAKEN and id.begins_with("u")
