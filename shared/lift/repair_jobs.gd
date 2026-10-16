class_name RepairJobs
extends RefCounted
## LFT-03: the repair jobs as server and client name them (Gameplay §3.3), in the Company's order
## (Proposed; consistent with the Manual's sample page): Power, Fuel, the pool of six, Start last.
## Also the Manual's wire form (Protocol.Msg.MANUAL): the list's kind, its can count and its jobs,
## all a client is ever told of the repair list. Never the seed, the plan, a place, a distance, a
## band, a spare or whether a job is done.

const COMPANY_ORDER: Array[StringName] = [&"power", &"fuel", &"magneto", &"drive_belt", &"brake_shoes", &"drum_gear",
	&"free_cage", &"rope_clamps", &"start"]
## The pool of six optional jobs.
const POOL: Array[StringName] = [&"magneto", &"drive_belt", &"brake_shoes", &"drum_gear", &"free_cage", &"rope_clamps"]
const KIND_NAMES: Array[String] = ["short", "standard", "full"]
## Each job's plates in the Manual: its parts and tools (data/text/manual: manual.plate.<name>).
const PLATES: Dictionary = {
	&"power": [&"fuse", &"wire_cutters"],
	&"fuel": [&"paraffin_can"],
	&"magneto": [&"magneto", &"spanner"],
	&"drive_belt": [&"drive_belt", &"hammer"],
	&"brake_shoes": [&"brake_shoe", &"spanner"],
	&"drum_gear": [&"drum_gear", &"spanner", &"hammer"],
	&"free_cage": [&"crowbar"],
	&"rope_clamps": [&"rope_clamp", &"spanner"],
	&"start": [],
}


## kind u8, cans u8, then one byte a job: its place in COMPANY_ORDER. Empty when a job is unknown.
static func encode(kind: int, cans: int, jobs: Array[StringName]) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray([clampi(kind, 0, 2), clampi(cans, 0, 255)])
	for job: StringName in jobs:
		var at: int = COMPANY_ORDER.find(job)
		if at < 0:
			return PackedByteArray()
		out.append(at)
	return out


## {kind, cans, jobs: Array[StringName]}, or {} when malformed (a repeat, an unknown job, out of
## the Company's order).
static func decode(payload: PackedByteArray) -> Dictionary:
	if payload.size() < 2 or payload[0] > 2:
		return {}
	var jobs: Array[StringName] = []
	var last: int = -1
	for i: int in range(2, payload.size()):
		var at: int = payload[i]
		if at >= COMPANY_ORDER.size() or at <= last:
			return {}
		last = at
		jobs.append(COMPANY_ORDER[at])
	return {"kind": payload[0], "cans": payload[1], "jobs": jobs}
