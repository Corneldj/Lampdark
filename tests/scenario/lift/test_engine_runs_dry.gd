extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-08 (Gameplay §3.6, §10.7): an engine running on a near-empty tank stops on the tick the tank
## empties; its beats stop and its run-up resets. A new start needs fuel first (a prime is refused
## dry), then a prime, a crank and a throttle; it catches again (engine_caught on both catches), and
## Start, done on the first, stays done.

const E = preload("res://tests/unit/lift/engine_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_it_stops_dry_and_starts_again_with_fuel() -> void:
	var s: Scenario = make({"seed": 7501, "fixture": E.T.C.scenario_fixture()})
	E.ready(s)
	var ann: MinerHandle = E.at(s, "ann", "engine_prime")
	var engine: WinderEngine = s.run.engine
	var tank: FuelTank = s.run.fuel
	E.prime(s, ann)
	E.move_to(s, ann, "engine_crank")
	var bob: MinerHandle = E.at(s, "bob", "engine_throttle")
	var caught: Array[int] = []
	engine.engine_caught.connect(func(t: int) -> void: caught.append(t))
	E.hold(s, ann, 200)
	assert_true(E.throttle_after_cue(s, bob, 0.5))
	assert_true(engine.is_running())
	var started_at: int = int(Variants.number(s.run.repair.done[&"start"]))
	tank.level_ticks = 100
	var emptied_at: Array[int] = [-1]
	var stopped_at: Array[int] = [-1]
	tank.emptied.connect(func() -> void: emptied_at[0] = s.run.tick)
	engine.engine_stopped.connect(func(_why: StringName) -> void: stopped_at[0] = s.run.tick)
	s.step(120)
	assert_ne(stopped_at[0], -1, "it stopped")
	assert_eq(stopped_at[0], emptied_at[0], "on the tick the tank emptied")
	assert_eq(engine.state, WinderEngine.State.COLD)
	assert_false(engine.run_up_complete(s.run))
	var from: int = s.run.noise.event_log.size()
	s.step(90)
	assert_eq(E.events(s, NoiseTypes.Type.ENGINE_RUNNING, from).size(), 0, "no beat once dry")
	# Dry: no prime.
	E.move_to(s, ann, "engine_prime")
	E.prime(s, ann)
	assert_eq(str(engine.refused.back()["why"]), "dry")
	# Fuel, then the whole start again.
	tank.level_ticks = FuelTank.unit_ticks()
	E.prime(s, ann)
	assert_eq(engine.state, WinderEngine.State.PRIMED)
	E.move_to(s, ann, "engine_crank")
	E.hold(s, ann, 200)
	assert_true(E.throttle_after_cue(s, bob, 0.5))
	assert_true(engine.is_running(), "running again")
	assert_eq(caught.size(), 2, "engine_caught on every catch")
	assert_eq(int(Variants.number(s.run.repair.done[&"start"])), started_at, "Start stays done from the first catch")
