extends GutTest
## NET-06's defender rule with stubbed wind-ups: each creature's condition, the hold of at most
## 150 ms, inputs stamped by the end counting, the Moth's issued shutter and the Stythe exception.

const E: int = 100

var run: RunState
var rule: DefenderRule
## slot 0's input this tick (null: none yet)
var current: InputBuffer.Consumed = null
var inside: bool = true
var lamp_on: bool = true


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	run = RunState.new()
	run.tick = E
	rule = DefenderRule.new()
	rule.input_for = func(_slot: int) -> InputBuffer.Consumed: return current
	current = null
	inside = true
	lamp_on = true


func _make_input(stamp: int, desired: int = 2) -> InputBuffer.Consumed:
	var c: InputBuffer.Consumed = InputBuffer.Consumed.new()
	c.record = InputRecord.new()
	c.record.desired = desired
	c.real = true
	c.shown_tick = stamp
	return c


func _windup(kind: StringName) -> DefenderRule.WindUp:
	var w: DefenderRule.WindUp = DefenderRule.WindUp.new()
	w.kind = kind
	w.defender_slot = 0
	w.started_tick = E - 10
	w.in_reach = func(_r: RunState) -> bool: return inside
	w.lit = func(_r: RunState, shut: bool) -> bool: return lamp_on and not shut
	return w


## Steps to the next tick with `input` applied and `effect` run as its movement, then the rule.
func _next(input: InputBuffer.Consumed, effect: Callable = Callable()) -> void:
	run.tick += 1
	current = input
	if effect.is_valid():
		effect.call()
	rule.tick(run)


func test_out_of_reach_at_the_end_misses_at_once() -> void:
	inside = false
	var w: DefenderRule.WindUp = _windup(&"tapper")
	assert_eq(rule.resolve(run, w), DefenderRule.Outcome.MISSED)
	assert_eq(w.decided_tick, E)


func test_tapper_step_stamped_before_the_end_escapes() -> void:
	var w: DefenderRule.WindUp = _windup(&"tapper")
	watch_signals(rule)
	assert_eq(rule.resolve(run, w), DefenderRule.Outcome.PENDING)
	_next(_make_input(E - 2))
	_next(_make_input(E - 1), func() -> void: inside = false)
	assert_eq(w.outcome, DefenderRule.Outcome.MISSED, "the step out of reach was issued before the end")
	assert_eq(w.decided_tick, E + 2)
	assert_signal_emitted(rule, "missed")


func test_tapper_step_stamped_after_the_end_lands() -> void:
	var w: DefenderRule.WindUp = _windup(&"tapper")
	rule.resolve(run, w)
	_next(_make_input(E + 1), func() -> void: inside = false)
	assert_eq(w.outcome, DefenderRule.Outcome.CONFIRMED, "issued after the end: it lands, at once")
	assert_eq(w.decided_tick, E + 1)


func test_the_hold_never_passes_150_ms() -> void:
	for kind: StringName in [&"tapper", &"moth", &"stythe"]:
		before_each()
		var w: DefenderRule.WindUp = _windup(kind)
		rule.resolve(run, w)
		for i: int in 6:
			_next(null)
		assert_eq(w.outcome, DefenderRule.Outcome.CONFIRMED, "%s: confirmed when the hold runs out" % kind)
		assert_eq(w.decided_tick, E + 3, "%s: no later than E + 150 ms" % kind)


func test_a_late_input_stamped_by_the_end_still_counts_inside_the_hold() -> void:
	var w: DefenderRule.WindUp = _windup(&"tapper")
	rule.resolve(run, w)
	_next(null)
	_next(null)
	_next(_make_input(E), func() -> void: inside = false)
	assert_eq(w.outcome, DefenderRule.Outcome.MISSED, "stamped at E, arriving at E + 150 ms: it counts")


func test_moth_shutter_issued_by_the_end_saves_though_it_closes_later() -> void:
	var w: DefenderRule.WindUp = _windup(&"moth")
	rule.resolve(run, w)
	_next(_make_input(E - 1, 3))
	assert_eq(w.outcome, DefenderRule.Outcome.MISSED, "the shutter press counts at once; the lamp is still burning")
	assert_true(w.shutter_issued)


func test_moth_shutter_after_the_end_does_not_save() -> void:
	var w: DefenderRule.WindUp = _windup(&"moth")
	rule.resolve(run, w)
	_next(_make_input(E + 1, 3))
	assert_eq(w.outcome, DefenderRule.Outcome.CONFIRMED)


func test_moth_stepping_into_the_dark_saves() -> void:
	var w: DefenderRule.WindUp = _windup(&"moth")
	rule.resolve(run, w)
	_next(_make_input(E - 1), func() -> void: lamp_on = false)
	assert_eq(w.outcome, DefenderRule.Outcome.MISSED)


func test_stythe_light_never_counts_only_reach() -> void:
	var w: DefenderRule.WindUp = _windup(&"stythe")
	w.lit = func(_r: RunState, _shut: bool) -> bool: return false
	assert_eq(rule.resolve(run, w), DefenderRule.Outcome.PENDING, "the Stythe ignores light at the end")
	_next(_make_input(E - 1, 2))
	_next(_make_input(E))
	assert_eq(w.outcome, DefenderRule.Outcome.PENDING, "a shutter opened before the end changes nothing")
	_next(_make_input(E), func() -> void: inside = false)
	assert_eq(w.outcome, DefenderRule.Outcome.MISSED, "leaving its reach still escapes")


func test_stythe_teammate_light_judged_once_at_the_end() -> void:
	var teammate_light: Array[bool] = [true]
	var w: DefenderRule.WindUp = _windup(&"stythe")
	w.at_end = func(_r: RunState) -> bool: return not teammate_light[0]
	assert_eq(rule.resolve(run, w), DefenderRule.Outcome.MISSED, "a teammate's light at the end, on server state")
	before_each()
	teammate_light[0] = false
	w = _windup(&"stythe")
	w.at_end = func(_r: RunState) -> bool: return not teammate_light[0]
	rule.resolve(run, w)
	teammate_light[0] = true
	for i: int in 3:
		_next(_make_input(E - 1))
	assert_eq(w.outcome, DefenderRule.Outcome.CONFIRMED, "light lit after the end is never held for")


func test_every_decision_is_logged() -> void:
	rule.resolve(run, _windup(&"tapper"))
	_next(_make_input(E + 1))
	assert_eq(rule.decisions.size(), 1)
	var d: Dictionary = rule.decisions[0]
	var outcome: String = d["outcome"]
	var end: int = d["end"]
	var stamps: PackedInt64Array = d["stamps"]
	assert_eq(outcome, "confirmed")
	assert_eq(end, E)
	assert_eq(stamps, PackedInt64Array([E + 1]))
