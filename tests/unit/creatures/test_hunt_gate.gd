extends GutTest
## CRT-01's hunt gate: the relax, cap, apex and chosen matrix, the signals, and the M1 defaults.

const StubCreature = preload("res://tests/scenario/kit/kit_creature.gd")

var run: RunState
var gate: HuntGate
var moth: StubCreature
var tapper: StubCreature
var stythe: StubCreature
var relax: bool = false
var apex: bool = false
var cap: int = -1


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	run = RunState.new()
	gate = HuntGate.new(CreatureLog.new())
	gate.relax_active = func() -> bool: return relax
	gate.apex_on = func() -> bool: return apex
	gate.cap_for = func(_crew: int) -> int: return cap
	relax = false
	apex = false
	cap = -1
	moth = _make(WorldIds.EntityKind.MOTH)
	tapper = _make(WorldIds.EntityKind.TAPPER)
	stythe = _make(WorldIds.EntityKind.STYTHE)


func _make(kind: WorldIds.EntityKind) -> StubCreature:
	var c: StubCreature = StubCreature.new(kind)
	var states: Array[CreatureState] = c.define_states()
	for s: CreatureState in states:
		c.states[s.name] = s
	c.state = states[0]
	gate.creatures.append(c)
	return c


func test_the_matrix() -> void:
	for case: Array in [
			# relax, apex, cap full, chosen -> allowed
			[false, false, false, true, true],
			[false, false, false, false, true],
			[true, false, false, true, false],
			[true, false, false, false, true],
			[true, true, false, true, true],
			[true, true, false, false, true],
			[false, false, true, true, false],
			[false, false, true, false, false],
			[true, true, true, true, false],
			[true, false, true, false, false]]:
		before_each()
		relax = case[0]
		apex = case[1]
		var full: bool = case[2]
		var chosen: bool = case[3]
		var want: bool = case[4]
		if full:
			cap = 1
			assert_true(gate.request_commit(run, tapper, 50, false), "fill the only place")
		var allowed: bool = gate.request_commit(run, moth, 7, chosen)
		assert_eq(allowed, want, "relax %s, apex %s, cap full %s, chosen %s" % [relax, apex, full, chosen])


func test_signals_once_each_with_miner_and_reason() -> void:
	watch_signals(gate)
	assert_true(gate.request_commit(run, moth, 7, true))
	assert_signal_emit_count(gate, "hunt_started", 1)
	var started: Array = get_signal_parameters(gate, "hunt_started")
	assert_eq(started, [moth, 7, true])
	gate.stand_down(run, moth, "lost them")
	gate.stand_down(run, moth, "lost them")
	assert_signal_emit_count(gate, "hunt_ended", 1)
	var ended: Array = get_signal_parameters(gate, "hunt_ended")
	assert_eq(ended, [moth, 7, "lost them"])


func test_a_committed_hunter_is_never_stood_down_by_the_cap() -> void:
	cap = 1
	assert_true(gate.request_commit(run, moth, 7, true))
	cap = 0
	gate.tick(run)
	assert_true(gate.is_hunting(moth), "the cap shrinking stands nobody down")
	assert_false(gate.request_commit(run, tapper, 8, false))


func test_states_that_fill_a_place_count() -> void:
	cap = 1
	stythe.state = stythe.states[&"hunt"]
	assert_eq(gate.active_count(), 1)
	assert_false(gate.request_commit(run, moth, 7, false), "the Stythe's hunting state holds the place")
	stythe.state = stythe.states[&"carry"]
	assert_true(gate.request_commit(run, moth, 7, false), "carrying fills no place")


func test_a_relax_ends_chosen_hunts_once_wind_ups_finish() -> void:
	assert_true(gate.request_commit(run, moth, 7, true))
	assert_true(gate.request_commit(run, tapper, 8, false))
	assert_true(gate.request_commit(run, stythe, 9, true))
	var w: CreatureWindUp = CreatureWindUp.new()
	stythe.wind_up = w
	relax = true
	gate.tick(run)
	assert_false(gate.is_hunting(moth), "a chosen hunt ends")
	assert_true(gate.is_hunting(tapper), "a consequence goes on")
	assert_true(gate.is_hunting(stythe), "a wind-up under way finishes first")
	w.outcome = CreatureWindUp.Outcome.MISSED
	gate.tick(run)
	assert_false(gate.is_hunting(stythe), "then it ends")
	assert_eq(moth.relax_started, 1, "creatures are told")


func test_defaults_while_the_director_is_absent() -> void:
	var plain: HuntGate = HuntGate.new()
	assert_false(Variants.flag(plain.relax_active.call()), "no relax")
	assert_eq(int(Variants.number(plain.pull_of.call(12))), 0, "every Pull is 0")
	assert_lt(int(Variants.number(plain.cap_for.call(1))), 0, "the cap never binds")
	plain.creatures.append(moth)
	assert_true(plain.request_commit(run, moth, 7, true), "hunts are always allowed")
	assert_eq(PullReader.new(plain).pull_of(3), 0)
