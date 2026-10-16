extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-06 with LFT-08's engine: four cans fill a Standard tank (Fuel done) and two miners start the
## engine, which runs four cans' worth on a full tank. Once it has burned one, a can poured while it
## runs adds one more: it stops dry five cans' worth after the catch, Fuel staying done throughout.
## At the shipped 300 s a can that is 20 minutes and 5 more, 25 in all (test_engine_burn checks
## those to the tick); here a can lasts SECONDS_PER_CAN, so the whole run takes a few thousand ticks.

const T = preload("res://tests/unit/lift/tank_world.gd")
const E = preload("res://tests/unit/lift/engine_world.gd")
const SECONDS_PER_CAN: float = 20.0


func test_a_can_poured_while_running_adds_a_can_of_running() -> void:
	var s: Scenario = make({"seed": 6201, "fixture": T.C.scenario_fixture(),
		"overrides": {"lift.engine_s_per_can": SECONDS_PER_CAN}})
	var can_ticks: int = FuelTank.unit_ticks()
	assert_eq(can_ticks, roundi(SECONDS_PER_CAN * Tuning.f(&"net.tick_hz")))
	T.camp(s, RepairList.Kind.STANDARD)
	var ann: MinerHandle = T.at_filler(s, "ann")
	var tank: FuelTank = s.run.fuel
	for i: int in 4:
		T.can_in_hand(s, ann)
		T.hold(s, ann, 66)
	assert_true(tank.done, "full: Fuel done")
	assert_true(tank.is_full(s.run))
	# Every other job done. Ann sets the dry can aside, primes and cranks; Bob throttles.
	for job: StringName in s.run.repair.list.jobs:
		if job != &"start" and not s.run.repair.is_done(job):
			s.run.repair.done[job] = s.run.tick
	s.run.inventory.hands_of(ann.entity_id).free_hand = null
	var engine: WinderEngine = s.run.engine
	E.move_to(s, ann, "engine_prime")
	E.prime(s, ann)
	E.move_to(s, ann, "engine_crank")
	var bob: MinerHandle = E.at(s, "bob", "engine_throttle")
	E.hold(s, ann, 200)
	assert_true(E.throttle_after_cue(s, bob, 0.5), "it caught")
	var caught: int = engine.caught_at
	var stopped: Array[int] = [-1]
	engine.engine_stopped.connect(func(_why: StringName) -> void: stopped[0] = s.run.tick)
	# Once it has burned a can's worth, Ann tops it up at the filler.
	assert_true(s.run_until(func(sc: Scenario) -> bool: return tank.capacity_ticks(sc.run) - tank.level_ticks >= can_ticks, 5 * can_ticks))
	var tile: Vector2i = T.beside_filler(s)
	s.run.movement.place(s.run, ann.entity_id, Vector2(tile) + Vector2(0.5, 0.5))
	ann.at(s.run.tick).face(rad_to_deg((tank.filler - (Vector2(tile) + Vector2(0.5, 0.5))).angle()))
	s.step(3)
	T.can_in_hand(s, ann)
	T.hold(s, ann, 66)
	assert_eq(tank.pours.size(), 5, "topped up while running")
	assert_almost_eq(float(Variants.number(tank.pours.back()["fills"])), 4.0, 1e-6, "the whole can")
	assert_true(engine.is_running())
	assert_true(s.run_until(func(_sc: Scenario) -> bool: return not engine.is_running(), 5 * can_ticks), "ran dry")
	assert_eq(stopped[0] - caught, (4 + 1) * can_ticks, "four cans from full, and one more for the can poured")
	assert_true(tank.is_empty())
	assert_true(tank.done, "running dry never clears Fuel")
	assert_false(tank.is_fuelled(), "but a dry tank fuels nothing")
