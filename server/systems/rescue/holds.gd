class_name Holds
extends SimSystem
## RSC-03's one hold system: every grab and every trap, through MNR-03's hooks. Who holds whom;
## a Tapper's ReStrike stays the same grab; holds stack as the design says (a drag tears a miner
## out of a trap, a broken pin leaves them Caught, an unconscious miner stays in the trap, a
## Grabbed miner cannot be grabbed again); the relax never frees and a dropped player's hold runs
## on. Only a teammate (BROKEN), the creature (TIMED_OUT, ABANDONED), a retreat or the self-rescue
## ends a grab. Server-only.

signal grab_begun(grab_id: int, kind: GrabHold.Kind, creature: int, victim: int)
signal grab_ended(grab_id: int, outcome: GrabHold.Outcome)
signal grab_timed_out(grab_id: int)
signal caught_begun(trap_id: int, kind: CaughtHold.Kind, victim: int)
signal caught_ended(trap_id: int, outcome: CaughtHold.Outcome, victim: int)

## grab id -> GrabHold (live and ended this run; ended ones stay for the Inquiry)
var grabs: Dictionary = {}
## victim -> CaughtHold
var caught: Dictionary = {}
var self_rescue: SelfRescue = SelfRescue.new()
## HAZ-06's trap-wound rule for a miner torn out of a man-trap: (victim) -> void.
var trap_wound: Callable = Callable()
## Every hold event, for RSC-07's Inquiry.
var events: Array[Dictionary] = []
var _next_id: int = 1
var _run: RunState = null


func stage() -> int:
	return StageTable.Stage.FALLS


func order() -> int:
	return 10


func system_name() -> String:
	return "Holds"


func bind(run: RunState) -> void:
	_run = run


## A grab on `victim` (CRT-09's pin, CRT-14's drag). Refused (-1) when the victim is Grabbed,
## dead, or unconscious for a pin; a Caught or unconscious victim can be grabbed (a drag of the
## unconscious is a body from the start). Returns the grab id.
func grab(run: RunState, victim: int, kind: GrabHold.Kind, creature: int, limit_ticks: int) -> int:
	var life: int = _life(run, victim)
	if life == MinerTransitions.Life.GRABBED or life == MinerTransitions.Life.DEAD or grab_of(victim) != null:
		return -1
	if life == MinerTransitions.Life.UNCONSCIOUS and kind != GrabHold.Kind.STYTHE_DRAG:
		return -1
	var g: GrabHold = GrabHold.new()
	g.id = _next_id
	_next_id += 1
	g.kind = kind
	g.creature = creature
	g.victim = victim
	g.limit_ticks = limit_ticks
	g.began_tick = run.tick
	if life == MinerTransitions.Life.UNCONSCIOUS:
		g.state = GrabHold.State.BODY
	grabs[g.id] = g
	var held: CaughtHold = caught_in(victim)
	if held != null and kind == GrabHold.Kind.STYTHE_DRAG:
		# The drag tears the miner out of any trap; a man-trap leaves its wound.
		_end_caught(run, held, CaughtHold.Outcome.TORN_OUT)
		if held.kind == CaughtHold.Kind.MAN_TRAP and trap_wound.is_valid():
			trap_wound.call(victim)
	if run.miner_state != null:
		run.miner_state.enter_grabbed(victim, g.mnr_kind(), creature)
	log_event(run, &"grab_begun", {"grab_id": g.id, "kind": g.kind, "creature": creature, "victim": victim})
	grab_begun.emit(g.id, g.kind, creature, victim)
	return g.id


## A silent pull freed the victim; the Tapper may still ReStrike this grab.
func suspend(run: RunState, grab_id: int) -> bool:
	var g: GrabHold = grabs.get(grab_id, null)
	if g == null or g.state != GrabHold.State.ACTIVE:
		return false
	g.state = GrabHold.State.SUSPENDED
	if run.miner_state != null:
		run.miner_state.end_grab(g.victim, true)
	log_event(run, &"grab_suspended", {"grab_id": grab_id, "elapsed": g.elapsed})
	return true


## A ReStrike landed: the same grab continues with its elapsed count. No new grab_begun.
func resume(run: RunState, grab_id: int) -> bool:
	var g: GrabHold = grabs.get(grab_id, null)
	if g == null or g.state != GrabHold.State.SUSPENDED or _life(run, g.victim) == MinerTransitions.Life.GRABBED:
		return false
	g.state = GrabHold.State.ACTIVE
	if run.miner_state != null:
		run.miner_state.enter_grabbed(g.victim, g.mnr_kind(), g.creature)
	log_event(run, &"grab_resumed", {"grab_id": grab_id, "elapsed": g.elapsed})
	return true


## Ends a grab with one of the listed outcomes. BROKEN, SELF_RESCUED and RETREAT free the victim
## (Upright and Hurt, or Caught again under a pin); TIMED_OUT lets MNR-03 drop them unconscious
## (a pin) or ends a body's drag; ABANDONED gives up a suspended pin.
func end_grab(run: RunState, grab_id: int, outcome: GrabHold.Outcome) -> bool:
	var g: GrabHold = grabs.get(grab_id, null)
	if g == null or g.state == GrabHold.State.ENDED or outcome == GrabHold.Outcome.NONE:
		return false
	var was: GrabHold.State = g.state
	g.state = GrabHold.State.ENDED
	g.outcome = outcome
	if run.miner_state != null and was != GrabHold.State.SUSPENDED:
		match outcome:
			GrabHold.Outcome.TIMED_OUT:
				run.miner_state.end_grab(g.victim, false)
			_:
				run.miner_state.end_grab(g.victim, was != GrabHold.State.BODY)
	self_rescue.checks.erase(grab_id)
	log_event(run, &"grab_ended", {"grab_id": grab_id, "outcome": outcome})
	grab_ended.emit(grab_id, outcome)
	return true


## A trap closes on `victim` (HAZ-01 to HAZ-03).
func catch(run: RunState, victim: int, kind: CaughtHold.Kind, trap_id: int) -> bool:
	if caught.has(victim) or _life(run, victim) == MinerTransitions.Life.DEAD:
		return false
	var h: CaughtHold = CaughtHold.new()
	h.trap_id = trap_id
	h.kind = kind
	h.victim = victim
	h.began_tick = run.tick
	caught[victim] = h
	if run.miner_state != null:
		run.miner_state.enter_caught(victim, h.source(), trap_id)
	log_event(run, &"caught_begun", {"trap_id": trap_id, "kind": kind, "victim": victim})
	caught_begun.emit(trap_id, kind, victim)
	return true


## Freed by a teammate or a lone struggle (FREED), or torn out (TORN_OUT).
func release_caught(run: RunState, victim: int, outcome: CaughtHold.Outcome) -> bool:
	var h: CaughtHold = caught_in(victim)
	if h == null or outcome == CaughtHold.Outcome.NONE:
		return false
	_end_caught(run, h, outcome)
	if run.miner_state != null and outcome == CaughtHold.Outcome.FREED:
		run.miner_state.release_caught(victim, "freed")
	return true


func grab_of(victim: int) -> GrabHold:
	for raw: Variant in grabs.keys():
		var g: GrabHold = grabs[raw]
		if g.victim == victim and g.is_live():
			return g
	return null


func grabbed_by(creature: int) -> Array[GrabHold]:
	var out: Array[GrabHold] = []
	var ids: Array = grabs.keys()
	ids.sort()
	for raw: Variant in ids:
		var g: GrabHold = grabs[raw]
		if g.creature == creature and g.is_live():
			out.append(g)
	return out


func caught_in(victim: int) -> CaughtHold:
	return caught.get(victim, null)


func is_held(victim: int) -> bool:
	return caught.has(victim) or (grab_of(victim) != null and grab_of(victim).state != GrabHold.State.SUSPENDED)


## Each tick (stage 9): ACTIVE grabs count; at the limit, grab_timed_out once, and a drag goes on
## as a body. Then the self-rescue. Nothing here looks at the relax or at connections.
func tick(run: RunState) -> void:
	_run = run
	var ids: Array = grabs.keys()
	ids.sort()
	for raw: Variant in ids:
		var g: GrabHold = grabs[raw]
		if g.state != GrabHold.State.ACTIVE:
			continue
		g.elapsed += 1
		if g.elapsed >= g.limit_ticks:
			log_event(run, &"grab_timed_out", {"grab_id": g.id, "elapsed": g.elapsed})
			if g.kind == GrabHold.Kind.STYTHE_DRAG:
				g.state = GrabHold.State.BODY
				if run.miner_state != null:
					run.miner_state.fall_unconscious(g.victim, "drag_ran_out")
					run.miner_state.enter_grabbed(g.victim, &"drag", g.creature)
			grab_timed_out.emit(g.id)
	self_rescue.tick(run, self)


func log_event(run: RunState, type: StringName, fields: Dictionary) -> void:
	var e: Dictionary = fields.duplicate()
	e["tick"] = run.tick
	e["type"] = type
	events.append(e)


func write_state(writer: SimStateWriter) -> void:
	writer.put_i64(_next_id)
	var ids: Array = grabs.keys()
	ids.sort()
	writer.put_i64(ids.size())
	for raw: Variant in ids:
		var g: GrabHold = grabs[raw]
		writer.put_i64(g.id)
		writer.put_i64(g.kind)
		writer.put_i64(g.victim)
		writer.put_i64(g.state)
		writer.put_i64(g.elapsed)
		var k: SelfRescue.Check = self_rescue.check_of(g.id)
		writer.put_i64(k.hits if k != null else -1)
		writer.put_i64(roundi(k.zone_start * 100.0) if k != null else 0)
		writer.put_i64(roundi(k.zone_size * 100.0) if k != null else 0)
		writer.put_i64(k.lockout_until if k != null else -1)
	var victims: Array = caught.keys()
	victims.sort()
	writer.put_i64(victims.size())
	for raw: Variant in victims:
		var h: CaughtHold = caught[raw]
		writer.put_i64(h.victim)
		writer.put_i64(h.trap_id)
		writer.put_i64(h.kind)


func _end_caught(run: RunState, h: CaughtHold, outcome: CaughtHold.Outcome) -> void:
	h.outcome = outcome
	caught.erase(h.victim)
	log_event(run, &"caught_ended", {"trap_id": h.trap_id, "outcome": outcome, "victim": h.victim})
	caught_ended.emit(h.trap_id, outcome, h.victim)


static func _life(run: RunState, victim: int) -> int:
	if run.miner_state == null or run.miner_state.miner(victim) == null:
		return MinerTransitions.Life.UPRIGHT
	return run.miner_state.life(victim)


## NET-09: the traps holding miners (a grab never: snapshots wait for none).
func save_state() -> Dictionary:
	var out: Dictionary = {}
	for raw: Variant in caught.keys():
		var h: CaughtHold = caught[raw]
		out[raw] = StateDicts.pick(h, ["trap_id", "kind", "victim", "began_tick"])
	return {"caught": out, "next_id": _next_id}


func load_state(_r: RunState, state: Dictionary) -> void:
	var saved: Dictionary = Variants.dict(state.get("caught", {}))
	for raw: Variant in saved.keys():
		var h: CaughtHold = CaughtHold.new()
		StateDicts.put(h, Variants.dict(saved[raw]))
		caught[int(Variants.number(raw))] = h
	_next_id = int(Variants.number(state.get("next_id", _next_id)))
