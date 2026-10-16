class_name OwnStatus
extends RefCounted
## The own miner's status as StatusWire carries it (to its owner only): its body cues, the self-rescue
## offer (RSC-03's SelfRescue: alone, the grab live, its one attempt unspent) or its failure, and the
## self-revive's count (RSC-09 fills the REVIVE flags). Server-only; the replication sends it on change.


static func of(run: RunState, miner: int) -> Dictionary:
	var out: Dictionary = {"cues": 0, "flags": 0, "revive_due_tick": 0, "revive_ticks": 0}
	if run.miner_state == null or run.miner_state.miner(miner) == null:
		return out
	out["cues"] = run.miner_state.cues(miner)
	var flags: int = 0
	if run.holds != null:
		var g: GrabHold = run.holds.grab_of(miner)
		if g != null and g.is_live():
			if SelfRescue.offered(run, g):
				flags |= StatusWire.SELF_RESCUE_OFFERED
			elif g.rescue_spent and g.state == GrabHold.State.ACTIVE:
				flags |= StatusWire.SELF_RESCUE_FAILED
	out["flags"] = flags
	return out
