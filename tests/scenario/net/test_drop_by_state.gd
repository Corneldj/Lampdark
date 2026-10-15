extends "res://tests/scenario/kit/scenario_test.gd"
## NET-11: each row of the drop table. A conscious miner: a Hand takes it where it stands, the lamp
## turned down on the belt. Unconscious or dead: nothing changes. The operator stands up from the
## board. A carrier sets the load down without a knock. Caught or Grabbed: the hold runs on. A timed
## action in progress is cancelled, nothing spent; an outcome already decided stays.
## (A stretcher end waits for MNR-14, which adds its set-down here.)

const R = preload("res://tests/unit/mnr/revolver_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")
const C = preload("res://tests/unit/mnr/chalk_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _world(run_seed: int) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": R.hall()})
	R.lit(s)
	var ann: MinerHandle = R.miner(s, "ann", Vector2i(3, 2))
	var bob: MinerHandle = R.miner(s, "bob", Vector2i(12, 2))
	s.step(3)
	return [s, ann, bob]


func _drop(s: Scenario, h: MinerHandle) -> Dictionary:
	h.at(s.run.tick).disconnect_at()
	s.run_until(func(sc: Scenario) -> bool: return not sc.run.drops.drops.is_empty(), 200)
	s.step(2)
	return s.run.drops.drops[s.run.drops.drops.size() - 1]


func test_a_conscious_miner_is_taken_by_a_hand() -> void:
	var w: Array = _world(1321)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var l: GauzeLamp = L.lit_in_hand(s, ann, LampRules.WICK_UP)
	s.step(2)
	var at: Vector2 = s.run.registry.get_entity(ann.entity_id).position
	var row: Dictionary = _drop(s, ann)
	s.step(10)
	assert_true(s.run.drops.hand_driven.has(ann.entity_id), "a Hand takes it")
	assert_eq(l.place, LampRules.Place.HOOK, "its lamp on the belt")
	assert_eq(l.wick, LampRules.WICK_DOWN, "turned down")
	assert_true(l.burning(), "still lit")
	assert_true(s.run.registry.get_entity(ann.entity_id).position.distance_to(at) < 0.2, "where it stands")
	assert_eq(s.net.seats.seat_of("ann").state, SeatTable.State.RESERVED, "the seat held")
	assert_string_contains(str(row["what"]), "a Hand takes it")


func test_unconscious_and_dead_change_nothing() -> void:
	var w: Array = _world(1322)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var bob: MinerHandle = w[2]
	assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.BLAST))
	s.run.miner_state.kill(bob.entity_id, "test")
	s.step(3)
	_drop(s, ann)
	_drop(s, bob)
	assert_eq(s.run.miner_state.life(ann.entity_id), MinerTransitions.Life.UNCONSCIOUS)
	assert_eq(s.run.miner_state.life(bob.entity_id), MinerTransitions.Life.DEAD)
	assert_true(s.run.drops.hand_driven.is_empty(), "no Hand for the fallen")


func test_the_operator_stands_up() -> void:
	var w: Array = _world(1323)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	s.run.closeups.open_for(s.run, ann.entity_id, CloseupKind.Kind.SWITCHBOARD, "test")
	s.step(1)
	assert_eq(s.run.closeups.operator(), ann.entity_id, "at the board")
	_drop(s, ann)
	assert_eq(s.run.closeups.operator(), 0, "stood up: nobody at the board")


func test_a_carrier_sets_the_load_down_without_a_knock() -> void:
	var w: Array = _world(1324)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var bob: MinerHandle = w[2]
	s.run.movement.place(s.run, bob.entity_id, Vector2(4.5, 2.5))
	assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.BLAST))
	s.step(3)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 42)
	s.step(1)
	assert_true(s.run.inventory.start_action(s.run, s.run.carry.lift_action(s.run, ann.entity_id, bob.entity_id)))
	s.step(45)
	assert_true(s.run.carry.is_carrying(ann.entity_id))
	var from: int = s.run.noise.event_log.size()
	_drop(s, ann)
	assert_false(s.run.carry.is_carrying(ann.entity_id), "set down")
	for e: NoiseSystem.Event in s.run.noise.event_log.slice(from):
		assert_ne(e.type, NoiseTypes.Type.CARRY_KNOCK, "no knock")


func test_caught_and_grabbed_holds_run_on() -> void:
	var w: Array = _world(1325)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var bob: MinerHandle = w[2]
	s.run.miner_state.enter_caught(ann.entity_id, &"man_trap", 9)
	s.run.miner_state.enter_grabbed(bob.entity_id, &"pin", 99)
	s.step(3)
	_drop(s, ann)
	_drop(s, bob)
	assert_eq(s.run.miner_state.life(ann.entity_id), MinerTransitions.Life.CAUGHT, "still Caught")
	assert_eq(s.run.miner_state.life(bob.entity_id), MinerTransitions.Life.GRABBED, "still Grabbed")
	assert_true(s.run.drops.hand_driven.is_empty(), "the Hand never self-rescues")


func test_a_timed_action_is_cancelled_and_an_outcome_stays() -> void:
	var w: Array = _world(1326)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var bob: MinerHandle = w[2]
	C.chalk(s, ann, ChalkMarks.Kind.CROSS)
	s.step(10)
	assert_true(s.run.inventory.actions.has(ann.entity_id), "chalking")
	_drop(s, ann)
	s.step(50)
	assert_eq(s.run.chalk.made.size(), 0, "cancelled, nothing made")
	s.run.miner_state.set_outcome(bob.entity_id, MinerTransitions.Outcome.LEFT_BELOW)
	s.step(2)
	_drop(s, bob)
	assert_eq(s.run.miner_state.miner(bob.entity_id).outcome, MinerTransitions.Outcome.LEFT_BELOW, "Left Below stays")
