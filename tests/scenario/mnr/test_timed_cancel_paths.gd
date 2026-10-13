extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-04 through real inputs: a pick-up cancelled by release, by walking out of range, by a
## state change or by inputs stopping (input_starved) spends nothing; held to the end it completes.

const W = preload("res://tests/unit/mnr/belt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _setup(run_seed: int) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": W.room()})
	W.light(s)
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = s.add_miner("ann", a)
	var spanner: int = W.put(s, ItemKinds.Kind.SPANNER, a + Vector2i(1, 0))
	ann.at(s.run.tick).face(0.0)
	s.step(4)
	var ends: Array[StringName] = []
	return [s, ann, spanner, ends]


## Records how ann's next action ends.
func _watch(s: Scenario, ann: MinerHandle, ends: Array[StringName]) -> void:
	s.on_tick = func(sc: Scenario) -> void:
		var act: TimedAction = sc.run.inventory.actions.get(ann.entity_id, null)
		if act != null and not act.cancelled.is_connected(_noop):
			act.cancelled.connect(func(_x: TimedAction, reason: StringName) -> void: ends.append(reason))
			act.cancelled.connect(_noop)


func _noop(_x: TimedAction, _reason: StringName) -> void:
	pass


func test_cancel_paths() -> void:
	for path: StringName in [TimedAction.RELEASED, TimedAction.RANGE, TimedAction.STATE, TimedAction.STARVED]:
		var parts: Array = _setup(21 + [TimedAction.RELEASED, TimedAction.RANGE, TimedAction.STATE, TimedAction.STARVED].find(path))
		var s: Scenario = parts[0]
		var ann: MinerHandle = parts[1]
		var spanner: int = parts[2]
		var ends: Array[StringName] = parts[3]
		_watch(s, ann, ends)
		# A starved hold ends during the outage; a hold still down after inputs resume would start afresh.
		ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 10 if path == TimedAction.RELEASED else (15 if path == TimedAction.STARVED else 60))
		s.step(8)
		match path:
			TimedAction.RANGE:
				ann.at(s.run.tick).move(180.0, InputRecord.Gait.RUN, 30)
			TimedAction.STATE:
				s.run.miner_state.fall_unconscious(ann.entity_id, "test")
			TimedAction.STARVED:
				ann.withhold_inputs(12)
		s.step(50)
		assert_true(s.run.inventory.world.items.has(spanner), "%s: nothing taken" % path)
		assert_null(W.belt(s, ann.entity_id).slots[0], "%s: nothing gained" % path)
		assert_eq(ends, [path] as Array[StringName], "cancelled by %s" % path)


func test_held_to_the_end_completes() -> void:
	var parts: Array = _setup(29)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var spanner: int = parts[2]
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 40)
	s.step(50)
	assert_false(s.run.inventory.world.items.has(spanner))
	assert_eq(W.belt(s, ann.entity_id).slots[0].kind, ItemKinds.Kind.SPANNER)
