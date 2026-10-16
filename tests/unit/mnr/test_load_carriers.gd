extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-14: carriers on a two-person load, as players drive them. Taking an end is 20 ticks of held
## interact, the lamp hooked from the start. One carrier cannot move a loaded stretcher or the drum
## gear; one miner carries an empty stretcher alone at walking pace. Two carriers move it at 2.5
## tiles/s (2.0 with one Hurt), each stepping 9 np every 10 ticks, standing exactly at its ends and
## never in rock; pulling apart, they knock it once (12 np, at its centre) and halt it. On a
## stretcher neither can change facing, on the drum gear both can. A carrier
## grabbed, caught or felled sets the load down that tick, with no knock; either carrier's interact
## sets it down at once, every lamp back in its hand.

const W = preload("res://tests/unit/mnr/load_world.gd")
const L = preload("res://tests/unit/mnr/lamp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _world(run_seed: int, kind: ItemKinds.Kind = ItemKinds.Kind.STRETCHER) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": W.hall()})
	var p: Array = W.setup(s, kind)
	return [s, p[0], p[1], p[2]]


func test_taking_an_end_is_20_ticks_held_and_hooks_the_lamp_at_once() -> void:
	var w: Array = _world(1401, ItemKinds.Kind.DRUM_GEAR)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var load: int = w[3]
	var lamp: GauzeLamp = L.lit_in_hand(s, ann)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 40)
	assert_true(s.run_until(func(sc: Scenario) -> bool: return sc.run.inventory.actions.has(ann.entity_id), 20), "the take starts")
	var a: TimedAction = s.run.inventory.actions[ann.entity_id]
	assert_eq(a.verb, &"take_load")
	assert_eq(a.ticks_needed, 20, "1 s at 20 Hz")
	assert_eq(lamp.place, LampRules.Place.HOOK, "the lamp hooks as the take starts")
	var done_at: Array[int] = [-1]
	a.completed.connect(func(_x: TimedAction) -> void: done_at[0] = s.run.tick)
	s.step(25)
	assert_eq(done_at[0] - a.started_tick + 1, 20, "20 ticks of held interact")
	assert_true(s.run.loads.carrying(ann.entity_id))
	assert_eq(s.run.inventory.held_bits(ann.entity_id) >> 8, ItemKinds.LOAD_END, "both hands on an end")
	assert_lt(s.run.registry.get_entity(ann.entity_id).position.distance_to(W.segment(s, load).front_end()), 1e-4, "at the front end")
	# Let go early: nothing taken, the lamp back.
	var v: Array = _world(1402, ItemKinds.Kind.DRUM_GEAR)
	var t: Scenario = v[0]
	var bob: MinerHandle = v[2]
	var bob_lamp: GauzeLamp = L.lit_in_hand(t, bob)
	bob.at(t.run.tick).hold(InputRecord.HOLD_INTERACT, 10)
	t.step(15)
	assert_false(t.run.loads.carrying(bob.entity_id), "released early: nothing taken")
	assert_eq(bob_lamp.place, LampRules.Place.HAND, "and the lamp back in the hand")


func test_one_carrier_cannot_move_a_loaded_stretcher_or_the_drum_gear() -> void:
	for kind: ItemKinds.Kind in [ItemKinds.Kind.STRETCHER, ItemKinds.Kind.DRUM_GEAR]:
		var w: Array = _world(1410 + kind, kind)
		var s: Scenario = w[0]
		var ann: MinerHandle = w[1]
		var bob: MinerHandle = w[2]
		var load: int = w[3]
		if kind == ItemKinds.Kind.STRETCHER:
			assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.BLAST))
			s.step(2)
			assert_true(s.run.loads.lay_body(s.run, load, bob.entity_id), "a body on it")
		W.take(s, ann)
		assert_true(s.run.loads.carrying(ann.entity_id))
		var from: int = s.run.noise.event_log.size()
		var at: Vector2 = s.run.registry.get_entity(load).position
		var me: Vector2 = s.run.registry.get_entity(ann.entity_id).position
		ann.at(s.run.tick).move(0.0, InputRecord.Gait.RUN, 60)
		s.step(62)
		assert_eq(s.run.registry.get_entity(load).position, at, "%s: nobody moves it alone" % ItemKinds.text_key(kind))
		assert_eq(s.run.registry.get_entity(ann.entity_id).position, me, "and its carrier stays at the end")
		assert_eq(W.knocks_since(s, from), 0)


func test_one_miner_carries_an_empty_stretcher_at_walking_pace() -> void:
	var w: Array = _world(1420)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var bob: MinerHandle = w[2]
	var load: int = w[3]
	W.take(s, ann)
	assert_true(s.run.loads.carrying(ann.entity_id))
	assert_eq(s.run.inventory.held_bits(ann.entity_id) >> 8, ItemKinds.LOAD_END, "both hands on its end")
	var from: float = s.run.registry.get_entity(load).position.x
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.RUN, 40)
	s.step(46)
	var moved: float = s.run.registry.get_entity(load).position.x - from
	assert_almost_eq(moved, 40 * Tuning.f(&"movement.walk_speed") / 20.0, 1e-3, "running held: walking pace")
	assert_eq(W.broken(s, load), "", "she stays at her end")
	# A second miner takes the other end: now a carry for two, at 2.5.
	bob.at(s.run.tick).walk_to(Vector2i(floori(W.segment(s, load).rear_end().x) - 1, 4))
	s.step(80)
	bob.at(s.run.tick).face(0.0).hold(InputRecord.HOLD_INTERACT, 26)
	s.step(29)
	assert_true(s.run.loads.carrying(bob.entity_id), "the other end taken")
	var from_two: float = s.run.registry.get_entity(load).position.x
	W.drive(s, ann, bob, 0.0, 40)
	s.step(46)
	assert_almost_eq(s.run.registry.get_entity(load).position.x - from_two, 40 * 2.5 / 20.0, 1e-3, "two carriers: 2.5 tiles/s")


func test_two_carriers_move_it_at_its_ends_and_step_every_10_ticks() -> void:
	for case: Array in [[ItemKinds.Kind.STRETCHER, 2.5, NoiseTypes.Type.STEP_STRETCHER], [ItemKinds.Kind.DRUM_GEAR, 2.0, NoiseTypes.Type.STEP_DRUM_GEAR]]:
		var kind: ItemKinds.Kind = int(Variants.number(case[0])) as ItemKinds.Kind
		var w: Array = _world(1430 + kind, kind)
		var s: Scenario = w[0]
		var ann: MinerHandle = w[1]
		var bob: MinerHandle = w[2]
		var load: int = w[3]
		W.both_take(s, ann, bob)
		assert_eq(s.run.loads.load_of_carrier(ann.entity_id), s.run.loads.load_of_carrier(bob.entity_id), "one load, two carriers")
		var faults: Array[String] = []
		var from_x: float = s.run.registry.get_entity(load).position.x
		var from_noise: int = s.run.noise.event_log.size()
		var moving: Array[int] = [-1, -1]
		s.on_tick = func(sc: Scenario) -> void:
			var why: String = W.broken(sc, load)
			if not why.is_empty():
				faults.append("tick %d: %s" % [sc.run.tick, why])
			var x: float = sc.run.registry.get_entity(load).position.x
			if moving[0] < 0 and x > from_x + 1e-6:
				moving[0] = sc.run.tick
			if moving[0] >= 0 and moving[1] < 0 and sc.run.tick - moving[0] == 39:
				moving[1] = roundi((x - from_x) * 1000.0)
		W.drive(s, ann, bob, 0.0, 60)
		s.step(64)
		assert_eq(faults, [] as Array[String], "%s: at its ends, never in rock" % ItemKinds.text_key(kind))
		assert_eq(moving[1], roundi(float(Variants.number(case[1])) * 2.0 * 1000.0), "%s: %.1f tiles/s" % [ItemKinds.text_key(kind), float(Variants.number(case[1]))])
		var steps: Dictionary = {}
		for e: NoiseSystem.Event in s.run.noise.event_log.slice(from_noise):
			if e.type == int(Variants.number(case[2])):
				var list: Array = steps.get(e.source_entity, [])
				list.append(e.tick)
				steps[e.source_entity] = list
				assert_eq(e.level_np, 9.0)
		assert_eq(steps.size(), 2, "both carriers step")
		for raw: Variant in steps.values():
			var ticks: Array = raw
			assert_eq(ticks.size(), 6, "60 ticks moving: a step every 10")
			for i: int in range(1, ticks.size()):
				assert_eq(int(Variants.number(ticks[i])) - int(Variants.number(ticks[i - 1])), 10)
		assert_eq(W.knocks_since(s, from_noise), 0, "agreeing carriers never knock")


func test_a_hurt_carrier_slows_the_stretcher_to_2_tiles_a_second() -> void:
	var w: Array = _world(1440)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var bob: MinerHandle = w[2]
	var load: int = w[3]
	W.both_take(s, ann, bob)
	s.run.miner_state.make_hurt(bob.entity_id, "test")
	s.step(2)
	var from_x: float = s.run.registry.get_entity(load).position.x
	W.drive(s, ann, bob, 0.0, 40)
	s.step(50)
	assert_almost_eq(s.run.registry.get_entity(load).position.x - from_x, 40 * 2.0 / 20.0, 1e-3, "2.0 tiles/s")


func test_facing_is_locked_on_a_stretcher_and_free_on_the_gear() -> void:
	for kind: ItemKinds.Kind in [ItemKinds.Kind.STRETCHER, ItemKinds.Kind.DRUM_GEAR]:
		var w: Array = _world(1450 + kind, kind)
		var s: Scenario = w[0]
		var ann: MinerHandle = w[1]
		var bob: MinerHandle = w[2]
		var load: int = w[3]
		W.both_take(s, ann, bob)
		ann.at(s.run.tick).face(90.0)
		bob.at(s.run.tick).face(270.0)
		W.drive(s, ann, bob, 0.0, 30)
		s.step(34)
		var heading: int = W.segment(s, load).heading
		if kind == ItemKinds.Kind.STRETCHER:
			assert_eq([s.run.movement.facing_of(ann.slot), s.run.movement.facing_of(bob.slot)], [heading, heading], "both face the stretcher's heading")
		else:
			var looking: int = s.run.movement.facing_of(ann.slot)
			assert_eq(looking, LoadSegment.degrees_u16(90.0), "the gear's carriers look about")


func test_a_carrier_grabbed_caught_or_felled_sets_it_down_that_tick() -> void:
	var n: int = 0
	for case: String in ["grabbed", "caught", "unconscious", "dead"]:
		n += 1
		var w: Array = _world(1460 + n)
		var s: Scenario = w[0]
		var ann: MinerHandle = w[1]
		var bob: MinerHandle = w[2]
		var load: int = w[3]
		var ann_lamp: GauzeLamp = L.lit_in_hand(s, ann)
		W.both_take(s, ann, bob)
		W.drive(s, ann, bob, 0.0, 200)
		s.step(10)
		var from: int = s.run.noise.event_log.size()
		var downed_at: Array[int] = [-1]
		s.run.loads.carry_ended.connect(func(_c: int, _l: int, _r: StringName) -> void:
			if downed_at[0] < 0:
				downed_at[0] = s.run.tick)
		var changed_at: Array[int] = [-1]
		s.run.miner_state.state_changed.connect(func(_e: int, _o: int, _n: int, _c: String) -> void:
			if changed_at[0] < 0:
				changed_at[0] = s.run.tick)
		match case:
			"grabbed":
				s.run.miner_state.enter_grabbed(bob.entity_id, &"pin", 99)
			"caught":
				s.run.miner_state.enter_caught(bob.entity_id, &"man_trap", 9)
			"unconscious":
				assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.BLAST))
			"dead":
				s.run.miner_state.kill(bob.entity_id, "test")
		s.step(3)
		assert_gte(changed_at[0], 0, case)
		assert_eq(downed_at[0], changed_at[0], "%s: set down the tick it happens" % case)
		assert_false(s.run.loads.carrying(ann.entity_id) or s.run.loads.carrying(bob.entity_id), "%s: both let go" % case)
		assert_eq(W.knocks_since(s, from), 0, "%s: no knock" % case)
		assert_eq(ann_lamp.place, LampRules.Place.HAND, "%s: the lamp back in the hand" % case)
		var at: Vector2 = s.run.registry.get_entity(load).position
		s.step(10)
		assert_eq(s.run.registry.get_entity(load).position, at, "%s: it lies where it went down" % case)


func test_either_carriers_interact_sets_it_down_at_once() -> void:
	var w: Array = _world(1470)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var bob: MinerHandle = w[2]
	var load: int = w[3]
	var lamp: GauzeLamp = L.lit_in_hand(s, ann)
	W.both_take(s, ann, bob)
	W.drive(s, ann, bob, 0.0, 20)
	s.step(24)
	assert_eq(lamp.place, LampRules.Place.HOOK, "hooked while carrying")
	bob.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 2)
	s.step(4)
	assert_false(s.run.loads.carrying(ann.entity_id) or s.run.loads.carrying(bob.entity_id), "both let go")
	assert_eq(lamp.place, LampRules.Place.HAND, "every lamp back in its hand")
	assert_eq(s.run.inventory.held_bits(ann.entity_id) >> 8, 0)
	var it: Item = s.run.inventory.world.item_at(load)
	assert_eq(int(Variants.number(it.state["heading"])), W.segment(s, load).heading, "its pose kept on its item")
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.WALK, 10)
	s.step(14)
	assert_gt(s.run.registry.get_entity(ann.entity_id).position.x, W.segment(s, load).front_end().x + 0.5, "free to walk off")


func test_carriers_pulling_apart_knock_once_at_12_np_and_halt() -> void:
	var w: Array = _world(1480)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var bob: MinerHandle = w[2]
	var load: int = w[3]
	W.both_take(s, ann, bob)
	W.drive(s, ann, bob, 0.0, 10)
	s.step(12)
	var from: int = s.run.noise.event_log.size()
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.WALK, 30)
	bob.at(s.run.tick).move(90.0, InputRecord.Gait.WALK, 30)
	s.step(20)
	assert_true(W.segment(s, load).halted, "halted while they pull apart")
	var at: Vector2 = W.segment(s, load).centre()
	s.step(8)
	assert_eq(W.segment(s, load).centre(), at, "and it stays put")
	s.step(6)
	assert_false(W.segment(s, load).halted, "both standing again: agreed, free")
	var knocks: Array[NoiseSystem.Event] = []
	for e: NoiseSystem.Event in s.run.noise.event_log.slice(from):
		if e.type == NoiseTypes.Type.CARRY_KNOCK:
			knocks.append(e)
	assert_eq(knocks.size(), 1, "one knock for one disagreement")
	assert_eq(knocks[0].level_np, 12.0, "a 12 np knock")
	assert_eq(knocks[0].source_entity, load)
	var centre: Vector2 = W.segment(s, load).centre()
	assert_true(knocks[0].origins.has(Vector2i(floori(centre.x), floori(centre.y))), "at the load's centre")
