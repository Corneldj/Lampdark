class_name SelfRescue
extends RefCounted
## RSC-03's self-rescue as the struggle (Gameplay §11.3, §11.11; Proposed after the first playtest,
## which found the one 50% roll a coin flip with no counterplay): a skill check. A needle sweeps a
## ring once every rescue.struggle_sweep_s; the victim presses interact (ActionRecord.Kind.STRUGGLE,
## judged at the tick their client showed, so a round trip costs nothing) while it is inside the
## zone; rescue.struggle_hits presses inside break the grab free (SELF_RESCUED). A miss shrinks the
## zone by rescue.struggle_zone_shrink_deg (to rescue.struggle_zone_min_deg), rattles (a STRUGGLE
## noise at the victim) and ignores presses for rescue.struggle_lockout_s, so mashing never pays.
## After a hit the zone moves ahead of the needle (rescue.struggle_zone_ahead_deg, on the seeded
## stream rescue.self_rescue: victim, grab id, hits). The crush runs on throughout.
##
## Who may struggle: anyone in a Tapper's pin (a teammate's silent pull stays the faster way out);
## in a Stythe's drag, only a miner alone (AloneRules), as before. Never a Hand.

class Check:
	extends RefCounted
	var hits: int = 0
	var zone_start: float = 0.0
	var zone_size: float = 70.0
	var epoch: int = 0
	var lockout_until: int = -1

## grab id -> Check
var checks: Dictionary = {}


static func offered(run: RunState, g: GrabHold) -> bool:
	if g == null or g.state != GrabHold.State.ACTIVE:
		return false
	if run.crew != null and Variants.flag(run.crew.is_hand_driven.call(g.victim)):
		return false
	if g.kind == GrabHold.Kind.TAPPER_PIN:
		return true
	return AloneRules.is_alone(run, g.victim)


static func sweep_ticks() -> int:
	return maxi(4, roundi(Tuning.f(&"rescue.struggle_sweep_s") * Tuning.f(&"net.tick_hz")))


## The needle's angle at tick `t` (degrees, 0 at the check's start, clockwise).
static func needle_deg(k: Check, t: int) -> float:
	return fposmod(float(t - k.epoch) * 360.0 / float(sweep_ticks()), 360.0)


static func in_zone(k: Check, angle: float) -> bool:
	return fposmod(angle - k.zone_start, 360.0) < k.zone_size


func check_of(grab_id: int) -> Check:
	return checks.get(grab_id, null)


## Once a tick (Holds): open a check for each grab now offered, drop the rest, judge the presses.
func tick(run: RunState, holds: Holds) -> void:
	for raw: Variant in checks.keys():
		var g: GrabHold = holds.grabs.get(raw, null)
		if g == null or not offered(run, g):
			checks.erase(raw)
	var ids: Array = holds.grabs.keys()
	ids.sort()
	for raw: Variant in ids:
		var g: GrabHold = holds.grabs[raw]
		if offered(run, g) and not checks.has(g.id):
			var k: Check = Check.new()
			k.epoch = run.tick
			k.zone_size = Tuning.f(&"rescue.struggle_zone_deg")
			_move_zone(run, g, k, run.tick)
			checks[g.id] = k
	if run.movement == null or run.inputs == null:
		return
	for slot: int in run.movement.miner_slots():
		var victim: int = run.movement.miner(slot).entity_id
		var g: GrabHold = holds.grab_of(victim)
		if g == null or not checks.has(g.id):
			continue
		var c: InputBuffer.Consumed = run.input_for(slot)
		if c == null:
			continue
		for a: ActionRecord in c.actions:
			var k: Check = checks.get(g.id, null)
			if a.kind == ActionRecord.Kind.STRUGGLE and k != null:
				press(run, holds, g, k, a.tick)


## One press, judged at the tick the victim's client showed (clamped to the check and to now).
func press(run: RunState, holds: Holds, g: GrabHold, k: Check, shown_tick: int) -> void:
	var t: int = clampi(shown_tick, k.epoch, run.tick)
	if t < k.lockout_until:
		return
	var angle: float = needle_deg(k, t)
	if in_zone(k, angle):
		k.hits += 1
		holds.log_event(run, &"struggle_hit", {"grab_id": g.id, "victim": g.victim, "hits": k.hits})
		if k.hits >= Tuning.i(&"rescue.struggle_hits"):
			checks.erase(g.id)
			holds.log_event(run, &"self_rescue", {"grab_id": g.id, "victim": g.victim, "success": true})
			holds.end_grab(run, g.id, GrabHold.Outcome.SELF_RESCUED)
			return
		_move_zone(run, g, k, t)
		return
	k.zone_size = maxf(Tuning.f(&"rescue.struggle_zone_min_deg"), k.zone_size - Tuning.f(&"rescue.struggle_zone_shrink_deg"))
	k.lockout_until = run.tick + roundi(Tuning.f(&"rescue.struggle_lockout_s") * Tuning.f(&"net.tick_hz"))
	holds.log_event(run, &"struggle_miss", {"grab_id": g.id, "victim": g.victim, "zone": k.zone_size})
	if run.noise != null and run.registry.has(g.victim):
		run.noise.emit(NoiseTypes.Type.STRUGGLE, run.registry.get_entity(g.victim).tile(), {"source": g.victim})


## A new zone ahead of where the needle is at `t`.
func _move_zone(run: RunState, g: GrabHold, k: Check, t: int) -> void:
	var rng: LbRng = run.stream(HashDomain.RESCUE_SELF_RESCUE, PackedInt64Array([g.victim, g.id, k.hits]))
	var ahead: Vector2 = Tuning.range_f(&"rescue.struggle_zone_ahead_deg")
	k.zone_start = fposmod(needle_deg(k, t) + ahead.x + rng.unit_double() * (ahead.y - ahead.x), 360.0)
