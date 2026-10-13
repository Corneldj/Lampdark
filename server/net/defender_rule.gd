class_name DefenderRule
extends SimSystem
## NET-06: escapes favour the defender. At a wind-up's end E the creature asks resolve(): if the
## landing condition fails on current state it misses; otherwise the landing is pending for up
## to net.defender_max_ms (3 ticks) while the defender's inputs are processed as normal. Only
## inputs stamped at or before E count: applied in order, they make it miss if they take the
## defender out of reach or, against the Moth, douse every light on them or step them into the
## dark. A defender input stamped after E confirms the landing at once; so does the hold running
## out. A shutter press stamped by E counts though its 0.2 s close ends later. Against the
## Stythe only leaving its reach counts: light made after its wind-up starts never does.
## A pending landing decides one outcome; it never feeds back into what a creature senses.

signal confirmed(windup: WindUp)
signal missed(windup: WindUp)

enum Outcome { PENDING = 0, CONFIRMED = 1, MISSED = 2 }

## What CRT-01's WindUp hands over at its end.
class WindUp:
	extends RefCounted
	var id: int = 0
	## &"moth", &"tapper", &"stythe" (and later kinds, which follow the reach rule).
	var kind: StringName = &""
	var defender_slot: int = -1
	var defender_entity: int = 0
	var started_tick: int = 0
	## E: the server tick the wind-up ends.
	var end_tick: int = 0
	## (run: RunState) -> bool: the defender is still inside the strike's reach.
	var in_reach: Callable = Callable()
	## The Moth: (run: RunState, own_shutter_issued: bool) -> bool, some light still on the
	## defender (their own lamp counts as dark once its shutter was issued by E).
	var lit: Callable = Callable()
	## Judged once, on server state at E, never held (a teammate's light against the Stythe).
	var at_end: Callable = Callable()
	var outcome: Outcome = Outcome.PENDING
	var decided_tick: int = -1
	var reason: String = ""
	var shutter_issued: bool = false
	## Stamps of the defender inputs that were weighed while pending.
	var stamps: PackedInt64Array = PackedInt64Array()

var max_ticks: int = 3
var pending: Array[WindUp] = []
## Every decision, for CRT-01's creature log and later the run record (NET-07).
var decisions: Array[Dictionary] = []
var _next_id: int = 1
## (slot) -> InputBuffer.Consumed: this tick's input; run.inputs.input_for unless a test stubs it.
var input_for: Callable = Callable()


func _init() -> void:
	if Tuning.current.has_key(&"net.defender_max_ms"):
		max_ticks = roundi(Tuning.f(&"net.defender_max_ms") / (1000.0 / Tuning.f(&"net.tick_hz")))


func stage() -> int:
	return StageTable.Stage.CREATURES


func order() -> int:
	return 0


func system_name() -> String:
	return "DefenderRule"


## At the wind-up's end (CRT-01 calls it in tick E, after this tick's inputs and movement).
## Returns the outcome so far: MISSED at once, or PENDING until confirmed or missed is emitted.
func resolve(run: RunState, w: WindUp) -> Outcome:
	w.id = _next_id
	_next_id += 1
	if w.end_tick == 0:
		w.end_tick = run.tick
	var c: InputBuffer.Consumed = _input(run, w.defender_slot)
	if c != null:
		_weigh_shutter(w, c)
	if w.at_end.is_valid() and not Variants.flag(w.at_end.call(run)):
		_decide(run, w, Outcome.MISSED, "condition failed at the end")
		return w.outcome
	if not _lands(run, w):
		_decide(run, w, Outcome.MISSED, "out of reach or dark at the end")
		return w.outcome
	pending.append(w)
	return Outcome.PENDING


## Each tick (stage 7, before the creatures): weigh the defender inputs applied this tick.
func tick(run: RunState) -> void:
	for w: WindUp in pending.duplicate():
		var c: InputBuffer.Consumed = _input(run, w.defender_slot)
		if c != null and c.real:
			w.stamps.append(c.shown_tick)
			if c.shown_tick > w.end_tick:
				_decide(run, w, Outcome.CONFIRMED, "a defender input stamped after the end arrived")
				continue
			_weigh_shutter(w, c)
			if not _lands(run, w):
				_decide(run, w, Outcome.MISSED, "escaped by an input issued before the end")
				continue
		if run.tick - w.end_tick >= max_ticks:
			_decide(run, w, Outcome.CONFIRMED, "the hold ran out")


func write_state(writer: SimStateWriter) -> void:
	writer.put_i64(_next_id)
	writer.put_i64(pending.size())
	for w: WindUp in pending:
		writer.put_i64(w.id)
		writer.put_string(w.kind)
		writer.put_i64(w.defender_slot)
		writer.put_i64(w.end_tick)
		writer.put_bool(w.shutter_issued)


func _lands(run: RunState, w: WindUp) -> bool:
	if not Variants.flag(w.in_reach.call(run)):
		return false
	if w.kind == &"moth" and w.lit.is_valid():
		return Variants.flag(w.lit.call(run, w.shutter_issued))
	# The Stythe (and every other kind): reach alone. Light never saves anyone from the Stythe.
	return true


## A shutter closed (or a douse) in an input stamped by E counts as issued, whenever it completes.
func _weigh_shutter(w: WindUp, c: InputBuffer.Consumed) -> void:
	if w.kind == &"moth" and c.shown_tick <= w.end_tick and (c.record.desired & 1) != 0:
		w.shutter_issued = true


func _decide(run: RunState, w: WindUp, outcome: Outcome, why: String) -> void:
	w.outcome = outcome
	w.decided_tick = run.tick
	w.reason = why
	pending.erase(w)
	var entry: Dictionary = {"id": w.id, "kind": w.kind, "slot": w.defender_slot, "entity": w.defender_entity,
		"started": w.started_tick, "end": w.end_tick, "decided": run.tick, "outcome": str(Outcome.keys()[outcome]).to_lower(),
		"reason": why, "stamps": w.stamps, "shutter_issued": w.shutter_issued}
	decisions.append(entry)
	Log.info("defender rule: %s wind-up %d on slot %d (end %d): %s at %d, %s" % [w.kind, w.id, w.defender_slot,
		w.end_tick, entry["outcome"], run.tick, why])
	if outcome == Outcome.CONFIRMED:
		confirmed.emit(w)
	else:
		missed.emit(w)


func _input(run: RunState, slot: int) -> InputBuffer.Consumed:
	if input_for.is_valid():
		return input_for.call(slot)
	return run.inputs.input_for(slot) if run.inputs != null else null
