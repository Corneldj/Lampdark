class_name StytheEligibility
extends RefCounted
## CRT-13 (Gameplay §7.4, §13.9): whom the Stythe may hunt, always an unlit, awake miner:
##   reach:     within stythe.reach_tiles of it, anywhere (walked into its reach, or felt it);
##   territory: in its territory (by path from the lair) and sensed;
##   range:     in its hunting range, past the unheard mark (SND-09, the miner's own tile, DIR-04's
##              ruling) or marked by the Pull (pull.threshold_marked, 50): it knows where they are;
##   anywhere:  Pull pull.threshold_anywhere (80) or more.
## A Hired Hand only by reach or territory, and only while no unlit human is within its sensing range
## (Proposed). Preference: the longest unheard, then the highest Pull, then the lowest id. Server-only.


## The row that makes `miner` eligible now ("" if none).
static func row(run: RunState, st: StytheCreature, miner: int) -> String:
	var e: SimEntity = run.registry.get_entity(miner)
	if e == null or not st.unlit(run, e.tile()) or not StytheSenses.awake(run, miner):
		return ""
	var hand: bool = is_hand(run, miner)
	if hand and _human_sensed(run, st):
		return ""
	if e.position.distance_to(st.position(run)) <= Tuning.f(&"stythe.reach_tiles") + 1e-9:
		return "reach"
	if st.senses.in_territory(run, st, e.tile()) and st.senses.senses(miner):
		return "territory"
	if hand:
		return ""
	var pull: float = pull_of(st, miner)
	if st.senses.in_hunting_range(run, st, e.tile()):
		var slot: int = slot_of(run, miner)
		if (slot >= 0 and run.heard != null and run.heard.past_unheard_mark(slot)) or pull >= Tuning.f(&"pull.threshold_marked"):
			return "range"
	if pull >= Tuning.f(&"pull.threshold_anywhere"):
		return "anywhere"
	return ""


## Every eligible miner, most preferred first.
static func ranked(run: RunState, st: StytheCreature) -> Array[int]:
	var rows: Array[Array] = []
	for m: int in StytheSenses.miners(run):
		if not row(run, st, m).is_empty():
			rows.append([m, unheard_s(run, m), pull_of(st, m)])
	rows.sort_custom(func(a: Array, b: Array) -> bool:
		var ua: float = a[1]
		var ub: float = b[1]
		if not is_equal_approx(ua, ub):
			return ua > ub
		var pa: float = a[2]
		var pb: float = b[2]
		if not is_equal_approx(pa, pb):
			return pa > pb
		var ia: int = a[0]
		var ib: int = b[0]
		return ia < ib)
	var out: Array[int] = []
	for r: Array in rows:
		out.append(r[0])
	return out


static func is_hand(run: RunState, miner: int) -> bool:
	return run.crew != null and Variants.flag(run.crew.is_hand_driven.call(miner))


static func pull_of(st: StytheCreature, miner: int) -> float:
	return float(Variants.number(st.system.gate.pull_of.call(miner))) if st.system != null else 0.0


## SND-09's unheard seconds (a Hand has no timer: 0).
static func unheard_s(run: RunState, miner: int) -> float:
	var slot: int = slot_of(run, miner)
	if slot < 0 or run.heard == null or is_hand(run, miner):
		return 0.0
	return run.heard.unheard_seconds(slot)


static func slot_of(run: RunState, miner: int) -> int:
	if run.movement == null:
		return -1
	for slot: int in run.movement.miner_slots():
		if run.movement.miner(slot).entity_id == miner:
			return slot
	return -1


static func _human_sensed(run: RunState, st: StytheCreature) -> bool:
	for s: Dictionary in st.senses.sensed:
		if not is_hand(run, int(Variants.number(s["miner"]))):
			return true
	return false
