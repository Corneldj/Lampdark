extends RefCounted
## Test systems for NET-01's loop and scenario tests. Each declares its stage and order.


## Appends "<stage>.<order>" to a shared log each tick.
class Recording:
	extends SimSystem
	var _stage: int
	var _order: int
	var log: PackedStringArray

	func _init(at_stage: int, at_order: int, shared_log: PackedStringArray) -> void:
		_stage = at_stage
		_order = at_order
		log = shared_log

	func stage() -> int:
		return _stage

	func order() -> int:
		return _order

	func system_name() -> String:
		return "recording_%d_%d" % [_stage, _order]

	func tick(_run: RunState) -> void:
		log.append("%d.%d" % [_stage, _order])


## Declares nothing: registration must fail.
class Undeclared:
	extends SimSystem


## Counts ticks it saw (used in the network stage to prove freeze keeps pumping).
class Counter:
	extends SimSystem
	var _stage: int
	var calls: int = 0
	var ticks_seen: PackedInt64Array = PackedInt64Array()

	func _init(at_stage: int) -> void:
		_stage = at_stage

	func stage() -> int:
		return _stage

	func order() -> int:
		return 0

	func system_name() -> String:
		return "counter_%d" % _stage

	func tick(run: RunState) -> void:
		calls += 1
		ticks_seen.append(run.tick)


## Applies scripted inputs: tick -> Array of ["spawn", x, y] or ["despawn", nth].
class ScriptedInputs:
	extends SimSystem
	var script_by_tick: Dictionary

	func _init(inputs: Dictionary) -> void:
		script_by_tick = inputs

	func stage() -> int:
		return StageTable.Stage.INPUTS

	func order() -> int:
		return 0

	func tick(run: RunState) -> void:
		for raw: Variant in Variants.array(script_by_tick.get(run.tick, [])):
			var command: Array = Variants.array(raw)
			if str(command[0]) == "spawn":
				run.registry.create(WorldIds.EntityKind.MINER, Vector2(Variants.number(command[1]), Variants.number(command[2])))
			elif str(command[0]) == "despawn":
				var ids: PackedInt64Array = run.registry.ids()
				if not ids.is_empty():
					run.registry.destroy(ids[int(Variants.number(command[1])) % ids.size()])


## Moves every miner a random step from its own stream each tick.
class Wander:
	extends SimSystem
	var _streams: Dictionary = {}

	func stage() -> int:
		return StageTable.Stage.MINERS

	func order() -> int:
		return 0

	func tick(run: RunState) -> void:
		for id: int in run.registry.ids():
			var entity: SimEntity = run.registry.get_entity(id)
			if entity.kind != WorldIds.EntityKind.MINER:
				continue
			if not _streams.has(id):
				_streams[id] = run.stream(HashDomain.HANDS, PackedInt64Array([id]))
			var rng: LbRng = _streams[id]
			var step: Vector2 = Vector2(rng.range(-3, 3), rng.range(-3, 3)) * 0.05
			run.registry.move(id, entity.position + step)

	func write_state(writer: SimStateWriter) -> void:
		var ids: Array = _streams.keys()
		ids.sort()
		writer.put_i64(ids.size())
		for id: Variant in ids:
			var rng: LbRng = _streams[id]
			writer.put_i64(int(Variants.number(id)))
			writer.put_i64(rng.get_state())


## Now and then drops an item next to a random miner, and sometimes removes one.
class Litter:
	extends SimSystem
	var _rng: LbRng = null
	var dropped: int = 0

	func stage() -> int:
		return StageTable.Stage.WORLD

	func order() -> int:
		return 0

	func tick(run: RunState) -> void:
		if _rng == null:
			_rng = run.stream(HashDomain.GEN_BASECAMP, PackedInt64Array())
		if _rng.chance_ppm(20000):
			run.registry.create(WorldIds.EntityKind.ITEM, Vector2(_rng.range(-40, 60), _rng.range(-40, 60)))
			dropped += 1
		if _rng.chance_ppm(10000):
			var ids: PackedInt64Array = run.registry.ids()
			var pick: int = ids[_rng.range(0, ids.size() - 1)] if not ids.is_empty() else 0
			var entity: SimEntity = run.registry.get_entity(pick)
			if entity != null and entity.kind == WorldIds.EntityKind.ITEM:
				run.registry.destroy(pick)

	func write_state(writer: SimStateWriter) -> void:
		writer.put_i64(_rng.get_state() if _rng != null else 0)
		writer.put_i64(dropped)


## Copies the change feed in the record stage.
class FeedTap:
	extends SimSystem
	var seen: Array[ChangeFeed.Change] = []

	func stage() -> int:
		return StageTable.Stage.RECORD

	func order() -> int:
		return 0

	func tick(run: RunState) -> void:
		seen.append_array(run.feed.changes())
