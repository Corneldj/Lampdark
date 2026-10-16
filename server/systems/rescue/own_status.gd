class_name OwnStatus
extends RefCounted
## The own miner's status as StatusWire carries it (to its owner only): its body cues, the struggle
## while one is offered (RSC-03's SelfRescue: its needle and zone, the hits made and needed), and the
## self-revive's count (RSC-09). Server-only; the replication sends it on change.


static func of(run: RunState, miner: int) -> Dictionary:
	var out: Dictionary = {"cues": 0, "flags": 0, "revive_due_tick": 0, "revive_ticks": 0}
	if run.miner_state == null or run.miner_state.miner(miner) == null:
		return out
	out["cues"] = run.miner_state.cues(miner)
	var flags: int = 0
	if run.holds != null:
		var g: GrabHold = run.holds.grab_of(miner)
		var k: SelfRescue.Check = run.holds.self_rescue.check_of(g.id) if g != null else null
		if k != null and SelfRescue.offered(run, g):
			flags |= StatusWire.STRUGGLE
			out["epoch"] = k.epoch
			out["sweep_ticks"] = SelfRescue.sweep_ticks()
			out["zone_start"] = k.zone_start
			out["zone_size"] = k.zone_size
			out["hits"] = k.hits
			out["needed"] = Tuning.i(&"rescue.struggle_hits")
			out["lockout_until"] = maxi(0, k.lockout_until)
	# RSC-09: the self-revive's count, for the status line's ring.
	if run.self_revive != null:
		var r: Dictionary = run.self_revive.status_of(run, miner)
		if Variants.flag(r.get("counting", false)):
			flags |= StatusWire.REVIVE_COUNTING
		elif Variants.flag(r.get("waiting", false)):
			flags |= StatusWire.REVIVE_WAITING
		out["revive_due_tick"] = int(Variants.number(r.get("due_tick", 0)))
		out["revive_ticks"] = int(Variants.number(r.get("ticks", 0)))
	if run.two_miner != null and run.two_miner.at_two_person_job(miner):
		flags |= StatusWire.AT_JOB
	out["flags"] = flags
	return out
