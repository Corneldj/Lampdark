class_name TrapEvents
extends RefCounted
## HAZ-01 to HAZ-03: what the traps do, for whoever listens (the Inquiry, the Draught, tests): a
## miner `caught` by a trap (a man-trap, a timber pin, a staple pit), and `freed` from one, by a
## teammate or a struggle (never torn out: a Stythe's drag is RSC-03's). Built on RSC-03's holds,
## which keep the trap's kind only while it holds. Server-only.

signal caught(trap_id: int, kind: CaughtHold.Kind, victim: int)
signal freed(miner: int, kind: CaughtHold.Kind)

## victim -> the kind of trap holding them.
var _kinds: Dictionary = {}


func bind(run: RunState) -> void:
	if run.holds == null:
		return
	run.holds.caught_begun.connect(func(trap_id: int, kind: CaughtHold.Kind, victim: int) -> void:
		_kinds[victim] = kind
		caught.emit(trap_id, kind, victim))
	run.holds.caught_ended.connect(func(_trap_id: int, outcome: CaughtHold.Outcome, victim: int) -> void:
		var kind: int = int(Variants.number(_kinds.get(victim, -1)))
		_kinds.erase(victim)
		if outcome == CaughtHold.Outcome.FREED and kind >= 0:
			freed.emit(victim, kind as CaughtHold.Kind))
