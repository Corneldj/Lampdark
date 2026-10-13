extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-04: a timed action completes only if held to its end and then applies its effect exactly
## once. Every cancel path (release, movement, a state change, a lost target, range, a partner
## letting go, input_starved) spends nothing. Toggle mode takes the same time. One at a time.

const W = preload("res://tests/unit/mnr/belt_world.gd")

var _bits: Dictionary = {}


func before_all() -> void:
	assert_true(Tuning.load_server())


## A scenario with ann (and bob), the inventory reading `_bits[slot]` as held input.
func _setup(run_seed: int) -> Array:
	_bits = {}
	var s: Scenario = make({"seed": run_seed, "fixture": W.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	# Beside her: a both-hold partner must stay within touch range (MNR-05).
	var bob: MinerHandle = s.add_miner("bob", s.fixture.spot("a") + Vector2i(0, -1))
	s.step(2)
	s.run.inventory.holds_source = func(_run: RunState, slot: int) -> int: return int(Variants.number(_bits.get(slot, 0)))
	return [s, ann, bob]


## An action of 1 s for `who`, counting its effects and recording how it ended.
func _action(s: Scenario, who: MinerHandle, effects: Array[int], ends: Array[StringName]) -> TimedAction:
	var a: TimedAction = TimedAction.make(who.entity_id, &"test", 1.0, InputRecord.HOLD_INTERACT)
	a.effect = func() -> void: effects[0] += 1
	a.completed.connect(func(_a: TimedAction) -> void: ends.append(&"completed"))
	a.cancelled.connect(func(_a: TimedAction, reason: StringName) -> void: ends.append(reason))
	assert_true(s.run.inventory.start_action(s.run, a))
	return a


func test_completes_once_on_its_last_tick() -> void:
	var parts: Array = _setup(1)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var effects: Array[int] = [0]
	var ends: Array[StringName] = []
	_bits[ann.slot] = InputRecord.HOLD_INTERACT
	var a: TimedAction = _action(s, ann, effects, ends)
	assert_eq(a.ticks_needed, 20)
	assert_false(s.run.inventory.start_action(s.run, TimedAction.make(ann.entity_id, &"other", 1.0, InputRecord.HOLD_INTERACT)),
		"one timed action per miner at a time")
	s.step(19)
	assert_eq(effects[0], 0, "nothing until the end")
	s.step(1)
	assert_eq(effects[0], 1, "applied on the 20th held tick")
	s.step(40)
	assert_eq(effects[0], 1, "exactly once")
	assert_eq(ends, [&"completed"] as Array[StringName])


func test_every_cancel_spends_nothing() -> void:
	var cases: Array[StringName] = [TimedAction.RELEASED, TimedAction.MOVED, TimedAction.STATE, TimedAction.TARGET,
		TimedAction.RANGE, TimedAction.STARVED, TimedAction.PARTNER]
	for i: int in cases.size():
		var reason: StringName = cases[i]
		var parts: Array = _setup(10 + i)
		var s: Scenario = parts[0]
		var ann: MinerHandle = parts[1]
		var bob: MinerHandle = parts[2]
		var effects: Array[int] = [0]
		var ends: Array[StringName] = []
		var ok: Array[bool] = [true]
		_bits[ann.slot] = InputRecord.HOLD_INTERACT
		_bits[bob.slot] = InputRecord.HOLD_INTERACT
		var a: TimedAction = _action(s, ann, effects, ends)
		a.needs_still = true
		a.valid = func() -> bool: return ok[0]
		a.target_point = Vector2(s.fixture.spot("a")) + Vector2(1.5, 0.5)
		a.reach = 1.5
		a.partner = bob.entity_id
		s.step(10)
		match reason:
			TimedAction.RELEASED:
				_bits[ann.slot] = 0
			TimedAction.MOVED:
				ann.at(s.run.tick).move(0.0, InputRecord.Gait.WALK, 10)
			TimedAction.STATE:
				s.run.miner_state.fall_unconscious(ann.entity_id, "test")
			TimedAction.TARGET:
				ok[0] = false
			TimedAction.RANGE:
				var far: Vector2 = Vector2(s.fixture.spot("a")) + Vector2(0.5, -1.5)
				s.run.registry.move(ann.entity_id, far)
				s.run.movement.miner(ann.slot).state.x = far.x
				s.run.movement.miner(ann.slot).state.y = far.y
			TimedAction.STARVED:
				s.run.inputs.input_starved.emit(ann.slot)
			TimedAction.PARTNER:
				_bits[bob.slot] = 0
		s.step(30)
		assert_eq(effects[0], 0, "%s: nothing spent" % reason)
		assert_eq(ends, [reason] as Array[StringName], "cancelled for %s" % reason)
		assert_false(s.run.inventory.actions.has(ann.entity_id))


func test_toggle_takes_the_same_time() -> void:
	var hold: HoldLatch = HoldLatch.new()
	var toggle: HoldLatch = HoldLatch.new()
	toggle.toggle = true
	var held_ticks: Array[int] = [0, 0]
	# Hold mode: the control down for 20 ticks. Toggle mode: pressed once, pressed again 20 later.
	for t: int in 40:
		if hold.sample(t < 20):
			held_ticks[0] += 1
		if toggle.sample(t == 0 or t == 20):
			held_ticks[1] += 1
	assert_eq(held_ticks, [20, 20] as Array[int])
	# Driven through the runner, both complete on the same tick; a second press stops it early.
	for mode: int in 3:
		var parts: Array = _setup(30 + mode)
		var s: Scenario = parts[0]
		var ann: MinerHandle = parts[1]
		var effects: Array[int] = [0]
		var ends: Array[StringName] = []
		var latch: HoldLatch = HoldLatch.new()
		latch.toggle = mode > 0
		_action(s, ann, effects, ends)
		var done_at: int = -1
		for t: int in 40:
			var down: bool = t < 20 if mode == 0 else (t == 0 or (mode == 2 and t == 10))
			_bits[ann.slot] = InputRecord.HOLD_INTERACT if latch.sample(down) else 0
			s.step(1)
			if effects[0] == 1 and done_at < 0:
				done_at = t
		if mode < 2:
			assert_eq(done_at, 19, "mode %d completes on the 20th tick" % mode)
		else:
			assert_eq(effects[0], 0, "a second toggle press stops it; it never shortens it")
			assert_eq(ends, [TimedAction.RELEASED] as Array[StringName])
