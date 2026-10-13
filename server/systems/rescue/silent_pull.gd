class_name SilentPull
extends RefCounted
## RSC-03's rescue action against a Tapper's pin (CRT-09): a teammate, Upright, holding interact
## within vision.touch_range_tiles of the pinned miner, range-checked against where the teammate's
## client showed the victim (NET-06, up to 150 ms back). It is a miner's interaction, so it may be
## rewound; the creature asks this, and never reads the rewind history itself.


## The pullers holding interact in touch range of `victim` this tick, ascending entity.
static func pullers(run: RunState, victim: int) -> Array[int]:
	var out: Array[int] = []
	var touch: float = Tuning.f(&"vision.touch_range_tiles")
	for slot: int in run.movement.miner_slots():
		var e: int = run.movement.miner(slot).entity_id
		if e == victim:
			continue
		var c: InputBuffer.Consumed = run.inputs.input_for(slot)
		if c == null or (c.record.holds & InputRecord.HOLD_INTERACT) == 0:
			continue
		if run.miner_state != null and run.miner_state.life(e) != MinerTransitions.Life.UPRIGHT:
			continue
		if run.rewind != null and not run.rewind.in_range_at(e, victim, touch, c.shown_tick):
			continue
		out.append(e)
	out.sort()
	return out
