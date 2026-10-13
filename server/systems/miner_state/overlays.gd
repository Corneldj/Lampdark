class_name MinerOverlays
extends RefCounted
## MNR-03's overlays and flag for one miner: Hurt (a 60 s timer, restarted by a second cause),
## Sick (a set of marks) and rock-touched (wears off; nothing cures it). Server-only: none of
## this, its timers or its causes reaches any client.

const TRAP_WOUND: StringName = &"trap_wound"
const INFESTED: StringName = &"infested"
const SOOT_LUNG: StringName = &"soot_lung"
const MARKS: Array[StringName] = [TRAP_WOUND, INFESTED, SOOT_LUNG]

## Tick at which Hurt ends; -1 when not hurt. Runs on under a trap wound (Proposed).
var hurt_until: int = -1
var marks: Dictionary = {}
var rock_touched_until: int = -1


func hurt(now: int) -> bool:
	return hurt_until > now


## MNR-01's single wound slot: Hurt or a trap wound, never both (x0.8, never x0.64).
func wound_slot(now: int) -> bool:
	return hurt(now) or marks.has(TRAP_WOUND)


func rock_touched(now: int) -> bool:
	return rock_touched_until > now


func write_state(writer: SimStateWriter) -> void:
	writer.put_i64(hurt_until)
	writer.put_i64(rock_touched_until)
	for mark: StringName in MARKS:
		writer.put_bool(marks.has(mark))
