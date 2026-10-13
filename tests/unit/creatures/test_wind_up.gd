extends GutTest
## CRT-01's wind-up: the 0.4 s floor, the condition judged at the end, and with NET-06 present
## an escape issued before the end on the defender's screen.

const StubCreature = preload("res://tests/scenario/kit/kit_creature.gd")

var run: RunState
var sys: CreatureSystem
var c: Creature
var inside: bool = true
var current: InputBuffer.Consumed = null


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	run = RunState.new()
	sys = CreatureSystem.new()
	c = StubCreature.new(WorldIds.EntityKind.TAPPER)
	assert_eq(sys.spawn(run, c, Vector2i(3, 3)), OK)
	inside = true
	current = null


func _reach() -> Callable:
	return func(_r: RunState) -> bool: return inside


func _until(end: int) -> void:
	while run.tick < end:
		run.tick += 1
		if run.defender != null:
			run.defender.tick(run)
		sys.tick(run)


func test_the_floor() -> void:
	var w: CreatureWindUp = sys.begin_wind_up(run, c, 0, 99, 0.35, _reach())
	assert_false(w.valid, "a 0.35 s wind-up is refused")
	assert_push_error("under the 0.4 s floor")
	w = sys.begin_wind_up(run, c, 0, 99, 0.5, _reach())
	assert_true(w.valid)
	assert_eq(w.end_tick - w.start_tick, 10, "0.5 s is 10 ticks")


func test_without_the_defender_rule_judged_at_the_end() -> void:
	var w: CreatureWindUp = sys.begin_wind_up(run, c, 0, 99, 0.5, _reach())
	_until(w.end_tick - 1)
	inside = false
	_until(w.end_tick)
	assert_eq(w.outcome, CreatureWindUp.Outcome.MISSED, "the condition is false at the end: it misses")
	w = sys.begin_wind_up(run, c, 0, 99, 0.5, _reach())
	inside = true
	_until(w.end_tick)
	assert_eq(w.outcome, CreatureWindUp.Outcome.LANDED)
	var log: Array[Dictionary] = sys.log.of_type(&"wind_up")
	assert_eq(log.size(), 2, "both logged")
	var first: String = log[0]["outcome"]
	assert_eq(first, "missed")


func test_with_the_defender_rule_an_escape_issued_before_the_end_misses() -> void:
	run.defender = DefenderRule.new()
	run.defender.input_for = func(_slot: int) -> InputBuffer.Consumed: return current
	var w: CreatureWindUp = sys.begin_wind_up(run, c, 0, 99, 0.5, _reach())
	_until(w.end_tick)
	assert_eq(w.outcome, CreatureWindUp.Outcome.PENDING, "in reach at the end: pending")
	current = InputBuffer.Consumed.new()
	current.record = InputRecord.new()
	current.real = true
	current.shown_tick = w.end_tick - 1
	inside = false
	_until(w.end_tick + 2)
	assert_eq(w.outcome, CreatureWindUp.Outcome.MISSED, "the step out, stamped before the end, saves them")
	assert_true(w.defender_applied)
	assert_true(Variants.flag(sys.log.of_type(&"wind_up")[0]["defender_rule"]), "the log says the rule applied")


func test_with_the_defender_rule_it_lands_within_150_ms() -> void:
	run.defender = DefenderRule.new()
	run.defender.input_for = func(_slot: int) -> InputBuffer.Consumed: return current
	var w: CreatureWindUp = sys.begin_wind_up(run, c, 0, 99, 0.5, _reach())
	_until(w.end_tick + 5)
	assert_eq(w.outcome, CreatureWindUp.Outcome.LANDED)
	var entry: Dictionary = sys.log.of_type(&"wind_up")[0]
	assert_eq(int(Variants.number(entry["tick"])), w.end_tick + 3, "confirmed when the hold runs out")


func test_cancel() -> void:
	run.defender = DefenderRule.new()
	run.defender.input_for = func(_slot: int) -> InputBuffer.Consumed: return current
	var w: CreatureWindUp = sys.begin_wind_up(run, c, 0, 99, 0.5, _reach())
	_until(w.end_tick)
	w.cancel(run, "retreat")
	assert_eq(w.outcome, CreatureWindUp.Outcome.CANCELLED)
	assert_eq(run.defender.pending.size(), 0, "the pending landing goes with it")
