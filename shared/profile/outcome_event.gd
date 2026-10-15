class_name OutcomeEvent
extends RefCounted
## MOD-01: the profile's append-only log (Proposed: event-sourced). Each entry is keyed, so applying
## it twice, or merging two copies that both hold it, changes nothing.
##   RUN_START (run, miner): the miner went below in that run, and is Below until it ends.
##   OUTCOME (run, miner, outcome): RSC-06's miner_outcome at Lamp Check (Gameplay §3.8, §11.9).
##   RUN_END (run, how): the run ended without Lamp Check: VOIDED (a public run's abnormal end: nothing
##     changes, its miners come back) or ABNORMAL (friends or Night Shift: resumes later; still Below).
##   HIRE (replaced miner, choice): the player picked one of the three fresh names offered.

enum Kind { RUN_START = 0, OUTCOME = 1, RUN_END = 2, HIRE = 3 }
## Gameplay §3.8: escaped returns; dead (brought home), Left Below and a wipe leave for good.
enum Outcome { ESCAPED = 0, DEAD = 1, LEFT_BELOW = 2, WIPE = 3 }
enum End { VOIDED = 0, ABNORMAL = 1 }

const LEAVES: Array[int] = [Outcome.DEAD, Outcome.LEFT_BELOW, Outcome.WIPE]
const OUTCOME_NAMES: Array[String] = ["escaped", "dead", "left_below", "wipe"]


static func run_start(run_uuid: String, miner: int, at: int) -> Dictionary:
	return {"kind": Kind.RUN_START, "run": run_uuid, "miner": miner, "at": at}


static func outcome(run_uuid: String, miner: int, what: Outcome, at: int) -> Dictionary:
	return {"kind": Kind.OUTCOME, "run": run_uuid, "miner": miner, "outcome": what, "at": at}


static func run_end(run_uuid: String, how: End, at: int) -> Dictionary:
	return {"kind": Kind.RUN_END, "run": run_uuid, "how": how, "at": at}


static func hire(replaced: int, choice: int, at: int) -> Dictionary:
	return {"kind": Kind.HIRE, "miner": replaced, "choice": choice, "at": at}


## The event's identity: one per (kind, run, miner); a HIRE is one per replaced miner.
static func key(e: Dictionary) -> String:
	return "%d|%s|%d" % [int(Variants.number(e.get("kind", -1))), str(e.get("run", "")), int(Variants.number(e.get("miner", 0)))]


## Two copies' versions of one event: an outcome that leaves for good beats any other (as STM-05's
## rule that deaths in any fork stand); otherwise the earlier stands.
static func stronger(a: Dictionary, b: Dictionary) -> Dictionary:
	if int(Variants.number(a.get("kind", -1))) == Kind.OUTCOME:
		var la: bool = LEAVES.has(int(Variants.number(a["outcome"])))
		var lb: bool = LEAVES.has(int(Variants.number(b["outcome"])))
		if la != lb:
			return a if la else b
	return a if _order(a) <= _order(b) else b


static func _order(e: Dictionary) -> String:
	return "%020d|%s" % [int(Variants.number(e.get("at", 0))), JSON.stringify(e)]


## Replay order: by time, then kind, run and miner, so every copy derives the same roster.
static func sort(events: Array[Dictionary]) -> void:
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ka: Array = [int(Variants.number(a.get("at", 0))), int(Variants.number(a.get("kind", 0))), str(a.get("run", "")),
			int(Variants.number(a.get("miner", 0)))]
		var kb: Array = [int(Variants.number(b.get("at", 0))), int(Variants.number(b.get("kind", 0))), str(b.get("run", "")),
			int(Variants.number(b.get("miner", 0)))]
		for i: int in ka.size():
			if ka[i] != kb[i]:
				return ka[i] < kb[i]
		return false)
