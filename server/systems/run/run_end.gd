class_name RunEnd
extends RefCounted
## LFT-11: the outcome record a finished run hands off (Gameplay §3.9's card, §11.9):
## {run_uuid, crew_size, up_count, miners: [{miner_id, name, lamp_number, outcome, dead, solo_rules}],
## wipe, deepest_ring, time_below_s, ended_tick, lamp_check_wait_s (a wipe's: at most
## rescue.wipe_lamp_check_wait_s for the last fall view)}.
## - The crew is the run's player miners, no Hired Hand; Up counts those who came up, a body brought
##   home included ('Up 4 of 5'; a wipe's 'Up none of N').
## - Outcome is "escaped" or "left_below"; dead with escaped reads "Dead, brought home".
## - Deepest is the deepest ring any of them stood in (Proposed), which RSC-06 names as a Level.
## - Time below is the run's own clock from its start (Proposed): it runs only while the run does, so
##   a Full run's sessions are summed and the gaps between knock-offs left out.
## Server-only until Lamp Check: RSC-06 shows it.

const OUTCOME_NAMES: Dictionary = {
	MinerTransitions.Outcome.ESCAPED: "escaped",
	MinerTransitions.Outcome.LEFT_BELOW: "left_below",
}


## `crew`: the counted miners; `outcomes`: miner -> MinerTransitions.Outcome; `identity_of`:
## (miner) -> {name, lamp_number} (MOD-03's roster), or invalid for the lamp check's number alone.
static func build(run: RunState, crew: Array[int], outcomes: Dictionary, wipe: bool, deepest: int, start_tick: int,
		identity_of: Callable) -> Dictionary:
	var miners: Array = []
	var up: int = 0
	for m: int in crew:
		var outcome: int = int(Variants.number(outcomes.get(m, MinerTransitions.Outcome.LEFT_BELOW)))
		var who: Dictionary = identity_of.call(m) if identity_of.is_valid() else {}
		var lamp: int = int(Variants.number(who.get("lamp_number", 0)))
		if lamp == 0 and run.inventory != null and run.inventory.hands.has(m):
			lamp = run.inventory.hands_of(m).lamp_check
		var dead: bool = run.miner_state != null and run.miner_state.miner(m) != null and run.miner_state.life(m) == MinerTransitions.Life.DEAD
		miners.append({"miner_id": m, "name": str(who.get("name", "")), "lamp_number": lamp,
			"outcome": OUTCOME_NAMES.get(outcome, "left_below"), "dead": dead,
			"solo_rules": run.alone_watch != null and run.alone_watch.ended_under_solo_rules(m)})
		if outcome == MinerTransitions.Outcome.ESCAPED:
			up += 1
	# A wipe's Lamp Check waits for the last victim's skippable fall view, at most this (RSC-06, Proposed).
	var wait: float = Tuning.f(&"rescue.wipe_lamp_check_wait_s") if wipe else 0.0
	return {"run_uuid": run.header.run_uuid, "crew_size": crew.size(), "up_count": up, "miners": miners, "wipe": wipe,
		"deepest_ring": deepest, "time_below_s": maxf(0.0, (run.tick - start_tick) / Tuning.f(&"net.tick_hz")), "ended_tick": run.tick,
		"lamp_check_wait_s": wait}
