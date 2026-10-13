class_name ChangeFeed
extends RefCounted
## The per-tick committed-change feed (NET-01, Proposed). Systems append typed changes during
## a tick; NET-07 (run record), NET-09 (journal) and NET-10 (migration) read them in stage 16,
## then the feed clears for the next tick.

enum Kind { ENTITY_CREATED, ENTITY_DESTROYED, ENTITY_MOVED, STATE_CHANGED, TILE_CHANGED, FALL, DEATH }


class Change:
	extends RefCounted
	var kind: Kind
	var tick: int
	var entity: int
	var data: Dictionary

	func _init(change_kind: Kind, at_tick: int, entity_id: int, payload: Dictionary) -> void:
		kind = change_kind
		tick = at_tick
		entity = entity_id
		data = payload


var _changes: Array[Change] = []
var _tick: int = 0


func begin_tick(tick: int) -> void:
	_tick = tick
	_changes.clear()


func append(kind: Kind, entity: int, data: Dictionary = {}) -> void:
	_changes.append(Change.new(kind, _tick, entity, data))


## This tick's changes, in the order they were made.
func changes() -> Array[Change]:
	return _changes.duplicate()


func size() -> int:
	return _changes.size()
