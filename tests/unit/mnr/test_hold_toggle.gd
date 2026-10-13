extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-15 (GDD §14.5): every held input works as hold or toggle, default Hold. In toggle mode a
## timed action (here the flint, 1.5 s) runs exactly as long as in hold mode, a second press stops
## it, and once it ends the client lets the latch go so the next press starts afresh.

const F = preload("res://tests/unit/mnr/input_frames.gd")
const W = preload("res://tests/unit/mnr/belt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")
const TICK_S: float = 0.05


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_every_held_input_defaults_to_hold() -> void:
	var store: BindingsStore = BindingsStore.new()
	for raw: Variant in InputRouter.HELD.keys():
		assert_false(store.is_toggle(str(raw)), "%s: Hold" % raw)
	for action: String in ["run", "crouch", "squint"]:
		assert_false(store.is_toggle(action))


func test_every_held_input_can_toggle() -> void:
	var held: Array[String] = ["run", "crouch", "squint"]
	for raw: Variant in InputRouter.HELD.keys():
		held.append(str(raw))
	for action: String in held:
		var store: BindingsStore = BindingsStore.new()
		store.set_toggle(action, true)
		var r: InputRouter = F.router("kbm", store)
		r.sample(F.frame(0.0, {action: true}))
		var on: Array = [r.record.holds, r.record.gait]
		r.sample(F.frame(0.05, {}))
		assert_eq([r.record.holds, r.record.gait], on, "%s: kept after the release" % action)
		r.sample(F.frame(0.1, {action: true}))
		r.sample(F.frame(0.15, {}))
		assert_eq([r.record.holds, r.record.gait], [0, InputRecord.Gait.WALK], "%s: a second press clears it" % action)


## Runs a flint relight with the router's records: `presses` are [from_tick, ticks down] of R.
## Returns [ticks the action ran, the lamp's state after, the action's end reason].
func _flint(toggle: bool, presses: Array, run_ticks: int) -> Array[int]:
	var s: Scenario = make({"seed": 7, "fixture": W.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	ann.at(0).lamp(false, LampRules.WICK_UP)
	s.step(1)
	var l: GauzeLamp = L.lit_in_hand(s, ann, LampRules.WICK_UP)
	s.run.lamps.snuff(s.run, l, "test")
	s.step(1)
	var store: BindingsStore = BindingsStore.new()
	store.set_toggle("relight", toggle)
	var r: InputRouter = F.router("kbm", store)
	r.sync_lamp(false, LampRules.WICK_UP)
	var base: int = s.run.tick
	for i: int in run_ticks:
		var down: bool = false
		for p: Variant in presses:
			var pr: Array = Variants.array(p)
			down = down or (i >= int(Variants.number(pr[0])) and i < int(Variants.number(pr[0])) + int(Variants.number(pr[1])))
		ann.at(base + i).input(r.sample(F.frame(i * TICK_S, {"relight": down})))
	var started: Array[int] = [-1]
	var ended: Array[int] = [-1, -1]
	var seen: Array[TimedAction] = []
	s.on_tick = func(sc: Scenario) -> void:
		var act: TimedAction = sc.run.inventory.actions.get(ann.entity_id, null)
		if act != null and not seen.has(act):
			seen.append(act)
			started[0] = sc.run.tick
		if act == null and not seen.is_empty() and ended[0] < 0:
			ended[0] = sc.run.tick
			ended[1] = l.state()
	s.step(run_ticks + 2)
	return [ended[0] - started[0], l.state(), seen.size()] as Array[int]


func test_toggle_runs_exactly_as_long_as_hold() -> void:
	var held: Array[int] = _flint(false, [[0, 45]], 60)
	var toggled: Array[int] = _flint(true, [[0, 1]], 60)
	assert_eq(held[1], GauzeLamp.State.OPEN, "hold: relit")
	assert_eq(toggled[1], GauzeLamp.State.OPEN, "toggle: relit")
	assert_eq(toggled[0], held[0], "the same length")
	assert_eq(held[0], Tuning.ticks(&"lamp.flint_time"))


func test_second_press_stops_it() -> void:
	var stopped: Array[int] = _flint(true, [[0, 1], [10, 1]], 60)
	assert_eq(stopped[1], GauzeLamp.State.OUT, "stopped at the second press: still out")
	assert_eq(stopped[2], 1, "one action, never restarted")
	assert_lt(stopped[0], Tuning.ticks(&"lamp.flint_time"))


func test_released_once_the_action_ends() -> void:
	var store: BindingsStore = BindingsStore.new()
	store.set_toggle("relight", true)
	var r: InputRouter = F.router("kbm", store)
	r.sample(F.frame(0.0, {"relight": true}))
	r.sample(F.frame(0.05, {}))
	assert_ne(r.record.holds & InputRecord.HOLD_RELIGHT, 0, "kept on from one press to the next")
	r.release_toggle("relight")
	r.sample(F.frame(0.1, {}))
	assert_eq(r.record.holds & InputRecord.HOLD_RELIGHT, 0, "the action ended: let go")
	r.sample(F.frame(0.15, {"relight": true}))
	assert_ne(r.record.holds & InputRecord.HOLD_RELIGHT, 0, "the next press starts afresh")
