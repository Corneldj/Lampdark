class_name BothHold
extends RefCounted
## MNR-05: a timed action every participant must hold (sharing oil, passing a flame, the two-miner
## timber pin). Built on MNR-04's TimedAction: each partner holds the same input and stays within
## touch range; any release cancels it with nothing changed and records who let go (`let_go`). Hired
## Hands never hold interact, so no both-hold involves one (§13.9).


## Adds `others` as partners of `a` (the initiator is its actor).
static func join(a: TimedAction, others: Array[int]) -> TimedAction:
	for o: int in others:
		if o != a.actor and not a.partners.has(o) and o != a.partner:
			a.partners.append(o)
	return a


## True if any of these miners is a Hired Hand.
static func involves_hand(run: RunState, miners: Array[int]) -> bool:
	if run.crew == null:
		return false
	for m: int in miners:
		if Variants.flag(run.crew.is_hand_driven.call(m)):
			return true
	return false
