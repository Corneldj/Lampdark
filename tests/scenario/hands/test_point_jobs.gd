extends "res://tests/scenario/kit/scenario_test.gd"
## MOD-08 (Gameplay §13.9, §11.4, §4.3): POINT takes the job at the lit spot. A body is lifted onto
## the Hand's shoulders (MNR-13's 2 s lift), carried as it follows, and set down where it stands at
## STOP; a stretcher end is taken (MNR-14) and carried; a paraffin can is picked up and carried; a
## caught miner is freed after hands.free_s beside them (a timber pin only with a human beside too).
## A Hand never rescues or frees anyone without a POINT, and picks up nothing it is not POINTed at.

const HW = preload("res://tests/unit/hands/hand_world.gd")
const W = preload("res://tests/unit/sound/signal_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


## Ann on the road facing east, a Hand following her, and the tile her POINT lights.
func _world(run_seed: int) -> Dictionary:
	var s: Scenario = make({"seed": run_seed, "fixture": HW.road(40)})
	var a: Vector2i = s.fixture.spot("a")
	var ann: MinerHandle = HW.human(s, "ann", a + Vector2i(6, 0), 0.0)
	var hand: int = HW.hand(s, a + Vector2i(2, 0))
	s.step(20)
	var lit: Vector2i = s.run.lamp_signals.point_target(s.run, ann.entity_id, ann.slot)
	return {"s": s, "ann": ann, "hand": hand, "lit": lit}


func _point(s: Scenario, ann: MinerHandle) -> void:
	W.signal_press(s, ann, LampSignalKind.Kind.POINT)
	s.step(5)


func test_a_body_is_carried_and_set_down_at_stop() -> void:
	var w: Dictionary = _world(4851)
	var s: Scenario = w["s"]
	var ann: MinerHandle = w["ann"]
	var hand: int = w["hand"]
	var lit: Vector2i = w["lit"]
	var bob: MinerHandle = s.add_miner("bob", lit)
	bob.brain = null
	s.step(2)
	assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.ROOF_FALL))
	s.step(40)
	assert_eq(s.run.carry.carrier_of(bob.entity_id), 0, "no rescue unbidden")
	_point(s, ann)
	assert_eq(HW.h_of(s, hand).state, HandController.State.JOB, "POINT: the job at the lit spot")
	s.step(260)
	assert_eq(s.run.carry.carrier_of(bob.entity_id), hand, "the Hand carries Bob")
	# Ann walks home west: the Hand follows with Bob on its shoulders.
	ann.at(s.run.tick).face(180.0).move(180.0, InputRecord.Gait.WALK, 60)
	var x0: float = HW.pos(s, hand).x
	s.step(120)
	assert_lt(HW.pos(s, hand).x, x0 - 2.0, "it follows at the load's pace")
	W.signal_press(s, ann, LampSignalKind.Kind.STOP)
	ann.at(s.run.tick).face(0.0)
	s.step(10)
	ann.at(s.run.tick).face(0.0)
	W.signal_press(s, ann, LampSignalKind.Kind.STOP)
	s.step(20)
	assert_eq(s.run.carry.carrier_of(bob.entity_id), 0, "STOP sets the body down")
	assert_lt(HW.pos(s, bob.entity_id).distance_to(HW.pos(s, hand)), 1.5, "where it stands")


func test_a_stretcher_end_is_taken() -> void:
	var w: Dictionary = _world(4852)
	var s: Scenario = w["s"]
	var ann: MinerHandle = w["ann"]
	var hand: int = w["hand"]
	var lit: Vector2i = w["lit"]
	var stretcher: int = s.run.loads.place(s.run, ItemKinds.Kind.STRETCHER, Vector2(lit) + Vector2(0.5, 0.5), 0)
	assert_ne(stretcher, 0)
	s.step(40)
	assert_false(s.run.loads.carrying(hand), "nothing taken unbidden")
	_point(s, ann)
	s.step(200)
	assert_true(s.run.loads.carrying(hand), "POINT: it takes an end of the stretcher")


func test_a_paraffin_can_is_picked_up_and_set_down() -> void:
	var w: Dictionary = _world(4853)
	var s: Scenario = w["s"]
	var ann: MinerHandle = w["ann"]
	var hand: int = w["hand"]
	var lit: Vector2i = w["lit"]
	var iw: ItemWorld = s.run.inventory.world
	var can: int = iw.put(s.run, iw.make(ItemKinds.Kind.PARAFFIN_CAN), Vector2(lit) + Vector2(0.5, 0.5))
	assert_ne(can, 0)
	s.step(40)
	assert_false(CanCarry.holds_can(s.run, hand), "nothing picked up unbidden")
	_point(s, ann)
	s.step(200)
	assert_true(CanCarry.holds_can(s.run, hand), "POINT: it picks up the can")
	W.signal_press(s, ann, LampSignalKind.Kind.STOP)
	s.step(10)
	assert_false(CanCarry.holds_can(s.run, hand), "STOP sets it down")


func test_a_caught_miner_is_freed() -> void:
	var w: Dictionary = _world(4854)
	var s: Scenario = w["s"]
	var ann: MinerHandle = w["ann"]
	var lit: Vector2i = w["lit"]
	var bob: MinerHandle = s.add_miner("bob", lit)
	bob.brain = null
	s.step(2)
	assert_true(s.run.holds.catch(s.run, bob.entity_id, CaughtHold.Kind.MAN_TRAP, 1))
	s.step(80)
	assert_true(s.run.holds.caught.has(bob.entity_id), "never freed unbidden")
	_point(s, ann)
	var hz: float = Tuning.f(&"net.tick_hz")
	assert_true(s.run_until(func(sc: Scenario) -> bool: return not sc.run.holds.caught.has(bob.entity_id),
		roundi((Tuning.f(&"hands.free_s") + 12.0) * hz)), "POINT: the Hand frees him")
	assert_eq(s.run.miner_state.life(bob.entity_id), MinerTransitions.Life.UPRIGHT)


func test_a_timber_pin_takes_a_human_beside() -> void:
	var w: Dictionary = _world(4855)
	var s: Scenario = w["s"]
	var ann: MinerHandle = w["ann"]
	var lit: Vector2i = w["lit"]
	var bob: MinerHandle = s.add_miner("bob", lit)
	bob.brain = null
	s.step(2)
	assert_true(s.run.holds.catch(s.run, bob.entity_id, CaughtHold.Kind.TIMBER_PIN, 2))
	_point(s, ann)
	s.step(roundi((Tuning.f(&"hands.free_s") + 10.0) * Tuning.f(&"net.tick_hz")))
	assert_true(s.run.holds.caught.has(bob.entity_id), "alone, a Hand cannot free a timber pin")
	ann.at(s.run.tick).walk_to(lit - Vector2i(1, 0))
	assert_true(s.run_until(func(sc: Scenario) -> bool: return not sc.run.holds.caught.has(bob.entity_id), 600),
		"with Ann beside him, the Hand is the second miner")

