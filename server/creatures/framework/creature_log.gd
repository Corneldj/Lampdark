class_name CreatureLog
extends RefCounted
## CRT-01's creature log: tells, wind-ups, hunts, grabs, retreats, hits, spawns and state
## changes, for the Inquiry card (RSC-07) and the run record (NET-07). Server-only: nothing
## here ever enters a client stream (NET-08 audits it).

signal logged(entry: Dictionary)

var entries: Array[Dictionary] = []


func add(tick: int, type: StringName, fields: Dictionary) -> Dictionary:
	var entry: Dictionary = fields.duplicate()
	entry["tick"] = tick
	entry["type"] = type
	entries.append(entry)
	logged.emit(entry)
	return entry


func of_type(type: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in entries:
		if e["type"] == type:
			out.append(e)
	return out
