class_name EntityRegistry
extends RefCounted
## Every entity of a run (NET-01): FND-07's IDs (from 1, never reused), deterministic
## iteration in ascending ID order, a cell-bucketed spatial index, and the packed per-tick
## mirror for the native stages. Server-only: no method here produces client-bound data.

var _ids: LbEntityIds = LbEntityIds.new()
## Ascending IDs of live entities.
var _order: PackedInt64Array = PackedInt64Array()
var _by_id: Dictionary = {}
## Vector2i cell -> PackedInt64Array of ascending IDs
var _cells: Dictionary = {}
var _feed: ChangeFeed = null


func _init(feed: ChangeFeed = null) -> void:
	_feed = feed


func create(kind: WorldIds.EntityKind, position: Vector2, flags: int = 0) -> SimEntity:
	var entity: SimEntity = SimEntity.new()
	entity.id = _ids.allocate()
	entity.kind = kind
	entity.position = position
	entity.flags = flags
	_by_id[entity.id] = entity
	_order.append(entity.id)  # IDs only rise, so the array stays sorted
	_bucket_add(entity.cell(), entity.id)
	if _feed != null:
		_feed.append(ChangeFeed.Kind.ENTITY_CREATED, entity.id, {"kind": kind})
	return entity


func destroy(id: int) -> bool:
	var entity: SimEntity = get_entity(id)
	if entity == null:
		return false
	_bucket_remove(entity.cell(), id)
	_order.remove_at(_order.bsearch(id))
	_by_id.erase(id)
	if _feed != null:
		_feed.append(ChangeFeed.Kind.ENTITY_DESTROYED, id)
	return true


func move(id: int, position: Vector2) -> void:
	var entity: SimEntity = get_entity(id)
	if entity == null:
		push_error("EntityRegistry.move: no entity %d" % id)
		return
	var old_cell: Vector2i = entity.cell()
	entity.position = position
	var new_cell: Vector2i = entity.cell()
	if new_cell != old_cell:
		_bucket_remove(old_cell, id)
		_bucket_add(new_cell, id)
	if _feed != null:
		_feed.append(ChangeFeed.Kind.ENTITY_MOVED, id, {"position": position})


func get_entity(id: int) -> SimEntity:
	if not _by_id.has(id):
		return null
	var entity: SimEntity = _by_id[id]
	return entity


func has(id: int) -> bool:
	return _by_id.has(id)


func count() -> int:
	return _order.size()


## Live IDs in ascending order: the only iteration order systems may use.
func ids() -> PackedInt64Array:
	return _order.duplicate()


## IDs in one cell, ascending.
func ids_in_cell(cell: Vector2i) -> PackedInt64Array:
	if not _cells.has(cell):
		return PackedInt64Array()
	var bucket: PackedInt64Array = _cells[cell]
	return bucket.duplicate()


## IDs in every cell within `radius` cells (Chebyshev) of `centre`, ascending.
func ids_near_cell(centre: Vector2i, radius: int) -> PackedInt64Array:
	var found: PackedInt64Array = PackedInt64Array()
	for dy: int in range(-radius, radius + 1):
		for dx: int in range(-radius, radius + 1):
			found.append_array(ids_in_cell(centre + Vector2i(dx, dy)))
	found.sort()
	return found


func next_id() -> int:
	return _ids.get_next()


## The packed per-tick mirror for native stages: parallel arrays in ascending ID order.
func packed_mirror() -> Dictionary:
	var kinds: PackedInt32Array = PackedInt32Array()
	var xy: PackedFloat64Array = PackedFloat64Array()
	var flag_values: PackedInt32Array = PackedInt32Array()
	for id: int in _order:
		var entity: SimEntity = _by_id[id]
		kinds.append(entity.kind)
		xy.append(entity.position.x)
		xy.append(entity.position.y)
		flag_values.append(entity.flags)
	return {"ids": _order.duplicate(), "kinds": kinds, "xy": xy, "flags": flag_values}


## Pushes the packed mirror to the native core (LbEntityMirror). Returns false if it refused.
func push_mirror(tick: int) -> bool:
	var ids_out: PackedInt64Array = _order.duplicate()
	var kinds: PackedInt32Array = PackedInt32Array()
	var xy: PackedFloat64Array = PackedFloat64Array()
	var flag_values: PackedInt32Array = PackedInt32Array()
	for id: int in _order:
		var entity: SimEntity = _by_id[id]
		kinds.append(entity.kind)
		xy.append(entity.position.x)
		xy.append(entity.position.y)
		flag_values.append(entity.flags)
	return LbEntityMirror.set_packed(tick, ids_out, kinds, xy, flag_values)


func write_state(writer: SimStateWriter) -> void:
	writer.put_i64(_ids.get_next())
	writer.put_i64(_order.size())
	for id: int in _order:
		var entity: SimEntity = _by_id[id]
		writer.put_i64(id)
		writer.put_i32(entity.kind)
		writer.put_f64(entity.position.x)
		writer.put_f64(entity.position.y)
		writer.put_i32(entity.flags)


func read_state(reader: SimStateReader) -> void:
	_by_id.clear()
	_cells.clear()
	_order = PackedInt64Array()
	_ids = LbEntityIds.new()
	_ids.restore(reader.get_i64())
	var count_read: int = reader.get_i64()
	for _i: int in count_read:
		var entity: SimEntity = SimEntity.new()
		entity.id = reader.get_i64()
		var kind_value: int = reader.get_i32()
		entity.kind = kind_value as WorldIds.EntityKind
		entity.position = Vector2(reader.get_f64(), reader.get_f64())
		entity.flags = reader.get_i32()
		_by_id[entity.id] = entity
		_order.append(entity.id)
		_bucket_add(entity.cell(), entity.id)


func _bucket_add(cell: Vector2i, id: int) -> void:
	var bucket: PackedInt64Array = _cells.get(cell, PackedInt64Array())
	bucket.insert(bucket.bsearch(id), id)
	_cells[cell] = bucket


func _bucket_remove(cell: Vector2i, id: int) -> void:
	if not _cells.has(cell):
		return
	var bucket: PackedInt64Array = _cells[cell]
	var index: int = bucket.bsearch(id)
	if index < bucket.size() and bucket[index] == id:
		bucket.remove_at(index)
	if bucket.is_empty():
		_cells.erase(cell)
	else:
		_cells[cell] = bucket
