extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-06: shutter and wick presses take effect exactly 4 ticks later, silently, with the pool
## moving linearly across the step from the press tick (as NET-05 predicts it); set down, hang
## and pick up take 20 ticks and keep wick and shutter; a douse shutters after 1 s and the owner
## reopens it in 0.2 s.

const W = preload("res://tests/unit/mnr/belt_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _setup(run_seed: int, wick: int = LampRules.WICK_NORMAL) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": W.room()})
	W.light(s, 0.0)
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	ann.at(0).lamp(false, wick)
	s.step(2)
	var l: GauzeLamp = L.lit_in_hand(s, ann, wick)
	s.step(2)
	return [s, ann, l]


## The owned radius each tick for `ticks`, starting with the tick the press lands on.
func _radii(s: Scenario, ann: MinerHandle, ticks: int) -> Array[float]:
	var out: Array[float] = []
	for _i: int in ticks:
		s.step(1)
		out.append(snappedf(s.run.light.grid.owned_radius(ann.entity_id), 0.001))
	return out


func test_shutter_and_wick_steps() -> void:
	var parts: Array = _setup(1)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var l: GauzeLamp = parts[2]
	var events: Array[Array] = []
	s.run.lamps.lamp_changed.connect(func(_l: GauzeLamp, what: StringName, _c: String) -> void: events.append([what, s.run.tick]))
	var noise_before: int = s.run.noise.event_log.size()
	assert_eq(LampRules.step_ticks(), 4)
	ann.at(s.run.tick).lamp(true, 1)
	var radii: Array[float] = _radii(s, ann, 12)
	var pressed: Array = events.filter(func(e: Array) -> bool: return e[0] == &"step_pressed")
	var done: Array = events.filter(func(e: Array) -> bool: return e[0] == &"shutter")
	assert_eq(pressed.size(), 1)
	assert_eq(done.size(), 1)
	assert_eq(int(Variants.number(Variants.array(done[0])[1])) - int(Variants.number(Variants.array(pressed[0])[1])), 4, "the shutter lands 4 ticks after the press")
	var k: int = radii.find(4.0, 0)
	var start: int = radii.rfind(4.0)
	assert_gte(k, 0)
	assert_eq(radii.slice(start, start + 5), [4.0, 3.0, 2.0, 1.0, 0.0] as Array[float], "linear across the step from the press tick")
	assert_true(l.shutter_closed)
	# Open again, then a wick step up: 4 -> 5.5 over the same 4 ticks.
	ann.at(s.run.tick).lamp(false, 1)
	s.step(8)
	ann.at(s.run.tick).lamp(false, 2)
	var up: Array[float] = _radii(s, ann, 12)
	var from: int = up.rfind(4.0)
	assert_eq(up.slice(from, from + 5), [4.0, 4.375, 4.75, 5.125, 5.5] as Array[float])
	assert_eq(l.wick, LampRules.WICK_UP)
	assert_eq(s.run.noise.event_log.size(), noise_before, "silent: 0 np")


func test_set_down_hang_pick_up_take_20_ticks() -> void:
	var parts: Array = _setup(2, LampRules.WICK_UP)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var l: GauzeLamp = parts[2]
	W.light(s)
	s.run.lamps.douse(s.run, l, 0)
	var seen: Array[TimedAction] = []
	s.on_tick = func(sc: Scenario) -> void:
		var a: TimedAction = sc.run.inventory.actions.get(ann.entity_id, null)
		if a != null and not seen.has(a):
			seen.append(a)
	ann.at(s.run.tick).face(0.0).hold(InputRecord.HOLD_SET_DOWN, 30)
	s.step(40)
	assert_eq(seen.size(), 1)
	assert_eq(seen[0].ticks_needed, 20, "set down in 1 s")
	assert_eq(l.state(), GauzeLamp.State.SET_DOWN_SHUTTERED, "keeps its shutter")
	assert_eq(l.wick, LampRules.WICK_UP, "and its wick")
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 30)
	s.step(40)
	assert_eq(seen.size(), 2)
	assert_eq(seen[1].ticks_needed, 20, "picked up in 1 s")
	assert_eq(l.state(), GauzeLamp.State.SHUTTERED)
	assert_eq(l.wick, LampRules.WICK_UP)
	# Hung: set down facing a hook.
	var hook: Vector2i = s.fixture.spot("a") + Vector2i(1, 0)
	s.run.lamps.hooks[hook] = true
	ann.at(s.run.tick).hold(InputRecord.HOLD_SET_DOWN, 30)
	s.step(40)
	assert_eq(l.place, LampRules.Place.HUNG, "hung on the hook")
	assert_eq(seen[2].ticks_needed, 20, "hung in 1 s")


func test_douse_and_reopen() -> void:
	var parts: Array = _setup(3)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var l: GauzeLamp = parts[2]
	var bob: MinerHandle = s.add_miner("bob", s.fixture.spot("a") + Vector2i(1, 0))
	s.step(2)
	var a: TimedAction = s.run.lamps.douse_action(s.run, bob.entity_id, ann.entity_id)
	assert_eq(a.ticks_needed, 20, "a douse takes 1 s")
	# The douse is started first: in the dark, a bare interact hold would start a feel (VIS-07).
	assert_true(s.run.inventory.start_action(s.run, a))
	s.run.inventory.holds_source = func(_run: RunState, slot: int) -> int: return InputRecord.HOLD_INTERACT if slot == bob.slot else 0
	s.step(19)
	assert_false(l.shutter_closed, "not before the second is up")
	s.step(2)
	s.run.inventory.holds_source = Callable()
	assert_true(l.shutter_closed, "doused")
	assert_eq(s.run.light.grid.owned_radius(ann.entity_id), 0.0)
	assert_false(Variants.flag(s.run.lamps.douse_action(s.run, bob.entity_id, ann.entity_id).valid.call()), "a douse only ever closes")
	# Her client takes the server's shutter (InventoryWire) and her next press opens it in 0.2 s.
	s.step(4)
	assert_true(Variants.flag(ann.connection.inventory["lamp_shut"]), "her client learns of the douse")
	ann.at(s.run.tick).lamp(true, 1)
	s.step(3)
	var events: Array[int] = []
	s.run.lamps.lamp_changed.connect(func(_l: GauzeLamp, what: StringName, _c: String) -> void:
		if what == &"step_pressed" or what == &"shutter":
			events.append(s.run.tick))
	ann.at(s.run.tick).lamp(false, 1)
	s.step(10)
	assert_false(l.shutter_closed, "she reopened it")
	assert_eq(events.size(), 2)
	assert_eq(events[1] - events[0], 4, "in 0.2 s")
