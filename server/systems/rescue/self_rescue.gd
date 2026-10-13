class_name SelfRescue
extends RefCounted
## RSC-03 (§11.11): a solo or lone-human miner's one self-rescue per grab. Offered only while
## AloneRules.is_alone(victim) and the grab's attempt is unspent, never to a Hand. Holding
## interact for rescue.self_rescue_hold_s completes it, and rescue.self_rescue_chance decides it
## from the seeded stream rescue.self_rescue (keys: victim, grab id): success frees the victim as
## a broken grab; failure spends the attempt and the grab runs on. Releasing early spends nothing,
## a ReStrike gives no new attempt, and a grab that ends during the hold voids it.

## grab id -> ticks held so far
var progress: Dictionary = {}


static func offered(run: RunState, g: GrabHold) -> bool:
	if g.state != GrabHold.State.ACTIVE or g.rescue_spent:
		return false
	if run.crew != null and Variants.flag(run.crew.is_hand_driven.call(g.victim)):
		return false
	return AloneRules.is_alone(run, g.victim)


static func roll(run: RunState, victim: int, grab_id: int) -> bool:
	var rng: LbRng = run.stream(HashDomain.RESCUE_SELF_RESCUE, PackedInt64Array([victim, grab_id]))
	return rng.chance_ppm(roundi(Tuning.f(&"rescue.self_rescue_chance") * 1000000.0))


## Once a tick: advance every offered hold whose victim holds interact.
func tick(run: RunState, holds: Holds) -> void:
	var need: int = roundi(Tuning.f(&"rescue.self_rescue_hold_s") * Tuning.f(&"net.tick_hz"))
	for raw: Variant in progress.keys():
		var g: GrabHold = holds.grabs.get(raw, null)
		if g == null or not offered(run, g):
			progress.erase(raw)
	for raw: Variant in holds.grabs.keys():
		var g: GrabHold = holds.grabs[raw]
		if not offered(run, g):
			continue
		if not _holding(run, g.victim):
			progress.erase(g.id)
			continue
		var held: int = int(Variants.number(progress.get(g.id, 0))) + 1
		progress[g.id] = held
		if held < need:
			continue
		progress.erase(g.id)
		g.rescue_spent = true
		var success: bool = roll(run, g.victim, g.id)
		holds.log_event(run, &"self_rescue", {"grab_id": g.id, "victim": g.victim, "success": success})
		if success:
			holds.end_grab(run, g.id, GrabHold.Outcome.SELF_RESCUED)


static func _holding(run: RunState, victim: int) -> bool:
	if run.movement == null or run.inputs == null:
		return false
	for slot: int in run.movement.miner_slots():
		if run.movement.miner(slot).entity_id == victim:
			var c: InputBuffer.Consumed = run.inputs.input_for(slot)
			return c != null and (c.record.holds & InputRecord.HOLD_INTERACT) != 0
	return false
