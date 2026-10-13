class_name CreatureWindUp
extends RefCounted
## CRT-01's wind-up: at least creatures.windup_min_s (0.4 s), then the strike lands only if its
## condition still holds at the end, judged on server state, and only if NET-06's defender rule
## finds no escape issued before the end on the defender's screen (up to 150 ms back, waiting up
## to 3 ticks). Effects are applied only once it has LANDED. cancel() stops it (a retreat).

signal finished(w: CreatureWindUp)

enum Outcome { RUNNING = 0, PENDING = 1, LANDED = 2, MISSED = 3, CANCELLED = 4 }

var id: int = 0
var creature: Creature = null
var target_slot: int = -1
var target_entity: int = 0
var start_tick: int = 0
var end_tick: int = 0
## (run) -> bool: the miner still within reach, and whatever else the creature's condition asks.
var condition: Callable = Callable()
## The Moth: (run, own_shutter_issued) -> bool, a light still on the target.
var lit: Callable = Callable()
## Judged once at the end, never held for (a teammate's light against the Stythe).
var at_end: Callable = Callable()
var outcome: Outcome = Outcome.RUNNING
var reason: String = ""
var defender_applied: bool = false
var valid: bool = true
var _defender: DefenderRule.WindUp = null


## Refuses (valid = false, an error) a wind-up shorter than creatures.windup_min_s.
static func make(c: Creature, run: RunState, slot: int, entity: int, duration_s: float, reach_condition: Callable) -> CreatureWindUp:
	var w: CreatureWindUp = CreatureWindUp.new()
	w.creature = c
	w.target_slot = slot
	w.target_entity = entity
	w.condition = reach_condition
	w.start_tick = run.tick
	if duration_s < Tuning.f(&"creatures.windup_min_s") - 1e-9:
		push_error("CreatureWindUp: %.2f s is under the %.1f s floor" % [duration_s, Tuning.f(&"creatures.windup_min_s")])
		w.valid = false
		w.outcome = Outcome.CANCELLED
		w.reason = "under the floor"
	w.end_tick = run.tick + roundi(duration_s * Tuning.f(&"net.tick_hz"))
	return w


func is_running() -> bool:
	return outcome == Outcome.RUNNING or outcome == Outcome.PENDING


## Called each tick by CreatureSystem; at the end tick it asks the defender rule.
func tick(run: RunState) -> void:
	if outcome != Outcome.RUNNING or run.tick < end_tick:
		return
	if run.defender == null:
		var holds: bool = Variants.flag(condition.call(run)) and (not at_end.is_valid() or Variants.flag(at_end.call(run)))
		if holds and lit.is_valid():
			holds = Variants.flag(lit.call(run, false))
		_finish(run, Outcome.LANDED if holds else Outcome.MISSED, "judged at the end")
		return
	var d: DefenderRule.WindUp = DefenderRule.WindUp.new()
	d.kind = creature.kind_name()
	d.defender_slot = target_slot
	d.defender_entity = target_entity
	d.started_tick = start_tick
	d.end_tick = end_tick
	d.in_reach = condition
	d.lit = lit
	d.at_end = at_end
	_defender = d
	run.defender.confirmed.connect(_on_confirmed.bind(run))
	run.defender.missed.connect(_on_missed.bind(run))
	outcome = Outcome.PENDING
	# An immediate miss is reported through `missed` (which finishes it); finish here only if not.
	if run.defender.resolve(run, d) == DefenderRule.Outcome.MISSED and outcome == Outcome.PENDING:
		_finish(run, Outcome.MISSED, d.reason)


func cancel(run: RunState, why: String) -> void:
	if not is_running():
		return
	if _defender != null and run.defender != null:
		run.defender.pending.erase(_defender)
	_finish(run, Outcome.CANCELLED, why)


func _on_confirmed(d: DefenderRule.WindUp, run: RunState) -> void:
	if d == _defender and outcome == Outcome.PENDING:
		defender_applied = d.stamps.size() > 0
		_finish(run, Outcome.LANDED, d.reason)


func _on_missed(d: DefenderRule.WindUp, run: RunState) -> void:
	if d == _defender and outcome == Outcome.PENDING:
		defender_applied = d.decided_tick > d.end_tick
		_finish(run, Outcome.MISSED, d.reason)


func _finish(run: RunState, result: Outcome, why: String) -> void:
	outcome = result
	reason = why
	if run.defender != null:
		if run.defender.confirmed.is_connected(_on_confirmed):
			run.defender.confirmed.disconnect(_on_confirmed)
		if run.defender.missed.is_connected(_on_missed):
			run.defender.missed.disconnect(_on_missed)
	if creature != null and creature.system != null:
		creature.system.log.add(run.tick, &"wind_up", {"id": id, "creature": creature.kind_name(), "target": target_entity,
			"start": start_tick, "end": end_tick, "outcome": str(Outcome.keys()[result]).to_lower(), "reason": why,
			"defender_rule": defender_applied})
	finished.emit(self)
	if creature != null:
		creature.on_wind_up_finished(run, self)
