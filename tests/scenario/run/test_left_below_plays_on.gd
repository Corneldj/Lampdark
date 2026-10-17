extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-11 (Gameplay §3.6, §11.9): a conscious miner left below hears the cage go up and plays on
## through its 40 s ride and any stop: Bob walks the whole while, the cage stopped in the dark among
## it; the run then ends for everyone on the surface's tick.

const K = preload("res://tests/unit/lift/cage_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_bob_plays_on_until_the_surface() -> void:
	var s: Scenario = make({"seed": 11401, "fixture": K.E.T.C.scenario_fixture()})
	K.ready(s)
	var cage: Cage = s.run.cage
	var ann: MinerHandle = K.aboard(s, "ann", 0)
	var bob: MinerHandle = K.aboard(s, "bob", 1)
	K.pull(s, ann)
	K.pull(s, bob)
	K.move_to(s, bob, s.run.base_camp.medbay_tables()[0])
	assert_true(s.run_until(func(_sc: Scenario) -> bool: return cage.is_departed(), K.bell_ticks() + 10))
	var surfaced: Array[int] = [-1]
	cage.cage_surfaced.connect(func(top: Dictionary) -> void: surfaced[0] = int(Variants.number(top["tick"])))
	# Bob walks back and forth; midway the cage stops (a stand-in pin) for 5 s and goes on.
	var moved: int = 0
	var was: Vector2 = s.run.registry.get_entity(bob.entity_id).position
	var hz: float = Tuning.f(&"net.tick_hz")
	var stop_at: int = s.run.tick + roundi(10.0 * hz)
	var go_at: int = stop_at + roundi(5.0 * hz)
	while not s.run.outcomes.ended and s.run.tick < go_at + ShaftRide.ride_ticks():
		if s.run.tick % 40 == 0:
			bob.at(s.run.tick).move(0.0 if (s.run.tick / 40) % 2 == 0 else 180.0, InputRecord.Gait.WALK, 30)
		if s.run.tick == stop_at:
			cage.ride.stop_for_pin(424242)
		if s.run.tick == go_at:
			cage.ride.resume(424242)
		s.step(1)
		var now: Vector2 = s.run.registry.get_entity(bob.entity_id).position
		if now.distance_to(was) > 1e-4:
			moved += 1
		was = now
	assert_true(s.run.outcomes.ended)
	assert_gt(moved, roundi(30.0 * hz), "he kept full control through the ride and its stop")
	assert_eq(s.run.outcomes.ended_tick, surfaced[0], "the run ends for everyone on the surface's tick")
	assert_eq(surfaced[0] - cage.ride.departed_at, ShaftRide.ride_ticks() + roundi(5.0 * hz), "40 s of ride, and the stop")
