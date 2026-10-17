extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-10 with LFT-08 (Gameplay §3.6, §10.7): the engine running dry during the hold bell cancels
## departure; the crew must fuel it, start it again and wait out a fresh run-up, then pull again,
## and only then does the cage leave.

const K = preload("res://tests/unit/lift/cage_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_dry_during_the_bell_then_a_fresh_start() -> void:
	var s: Scenario = make({"seed": 10701, "fixture": K.E.T.C.scenario_fixture()})
	K.ready(s)
	var cage: Cage = s.run.cage
	var engine: WinderEngine = s.run.engine
	var ann: MinerHandle = K.aboard(s, "ann", 0)
	K.pull(s, ann)
	assert_eq(cage.state, Cage.State.BELL)
	s.run.fuel.level_ticks = 60
	assert_true(s.run_until(func(_sc: Scenario) -> bool: return not engine.is_running(), 80), "dry mid-bell")
	s.step(2)
	assert_eq(cage.state, Cage.State.WAITING, "departure cancelled")
	s.step(K.bell_ticks())
	assert_false(cage.is_departed())
	# Fuel, a fresh start (prime, crank, throttle) and run-up; then the pull again.
	s.run.fuel.level_ticks = FuelTank.unit_ticks()
	var bob: MinerHandle = K.E.at(s, "bob", "engine_prime")
	K.E.prime(s, bob)
	K.E.move_to(s, bob, "engine_crank")
	var cid: MinerHandle = K.E.at(s, "cid", "engine_throttle")
	K.E.hold(s, bob, 200)
	assert_true(K.E.throttle_after_cue(s, cid, 0.5))
	assert_true(engine.is_running(), "caught again")
	K.pull(s, ann)
	assert_eq(str(cage.refused.back()["why"]), "run-up", "a fresh run-up first")
	assert_true(s.run_until(func(sc: Scenario) -> bool: return engine.run_up_complete(sc.run), 1300))
	# Bob and Cid aboard too (three conscious): Ann's pull alone is not enough now.
	K.move_to(s, bob, K.cord_tiles(s)[1])
	K.face(s, bob, K.cord_tiles(s)[1])
	K.move_to(s, cid, K.cord_tiles(s)[2])
	K.face(s, cid, K.cord_tiles(s)[2])
	K.pull(s, ann)
	K.pull(s, bob)
	assert_eq(cage.state, Cage.State.BELL)
	assert_true(s.run_until(func(_sc: Scenario) -> bool: return cage.is_departed(), K.bell_ticks() + 10), "and it leaves")
