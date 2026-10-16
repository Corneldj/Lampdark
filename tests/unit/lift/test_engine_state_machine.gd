extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-08: the engine's states. Priming is refused until every other job is done and the tank holds
## paraffin, and takes 60 ticks; the crank and throttle exist only once primed; the crank's cue
## comes on the tick the stroke reaches its top (80 ticks after it is taken), with a 20 np heave
## from the stroke's start and the winder shuddering; a catch runs it, fires engine_caught and marks
## Start done once; the run-up is complete after 60 s of running and not before; a save keeps the
## state, the run-up and the fixtures' entities.

const E = preload("res://tests/unit/lift/engine_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_priming_waits_for_the_jobs_and_the_fuel() -> void:
	var s: Scenario = make({"seed": 7001, "fixture": E.T.C.scenario_fixture()})
	E.T.camp(s, RepairList.Kind.SHORT)
	var ann: MinerHandle = E.at(s, "ann", "engine_prime")
	var engine: WinderEngine = s.run.engine
	E.prime(s, ann)
	assert_eq(str(engine.refused.back()["why"]), "jobs left", "Power and Fuel not done")
	s.run.repair.mark_done(s.run, &"power")
	s.run.repair.done[&"fuel"] = s.run.tick
	E.prime(s, ann)
	assert_eq(str(engine.refused.back()["why"]), "dry", "the tank holds nothing")
	assert_null(engine.crank, "no crank or throttle to take")
	s.run.fuel.level_ticks = 6000
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 66)
	assert_true(s.run_until(func(sc: Scenario) -> bool: return sc.run.inventory.actions.has(ann.entity_id), 20))
	var a: TimedAction = s.run.inventory.actions[ann.entity_id]
	assert_eq(a.verb, &"prime_engine")
	assert_eq(a.ticks_needed, 60, "3 s")
	s.step(66)
	assert_eq(engine.state, WinderEngine.State.PRIMED)
	assert_not_null(engine.crank, "primed: the crank and throttle are there")


func test_the_crank_cues_at_its_top_and_a_throttle_catches() -> void:
	var s: Scenario = make({"seed": 7002, "fixture": E.T.C.scenario_fixture()})
	E.ready(s)
	var ann: MinerHandle = E.at(s, "ann", "engine_prime")
	var bob: MinerHandle = E.at(s, "bob", "engine_crank")
	var cid: MinerHandle = E.at(s, "cid", "engine_throttle")
	var engine: WinderEngine = s.run.engine
	var caught: Array[int] = []
	engine.engine_caught.connect(func(t: int) -> void: caught.append(t))
	E.prime(s, ann)
	var from: int = s.run.noise.event_log.size()
	var looks: Array[int] = []
	s.on_tick = func(_sc: Scenario) -> void:
		if looks.is_empty() or looks.back() != engine.look():
			looks.append(engine.look())
	E.hold(s, bob, 200)
	assert_true(E.throttle_after_cue(s, cid, 0.5))
	s.on_tick = Callable()
	var cranks: Array[NoiseSystem.Event] = E.events(s, NoiseTypes.Type.ENGINE_CRANK, from)
	assert_eq(cranks.size(), 2, "the heave and the clank")
	assert_eq(cranks[1].tick - cranks[0].tick, 80, "the cue on the tick the 4 s stroke reaches its top")
	assert_eq(cranks[0].level_np, 20.0)
	assert_almost_eq(cranks[0].duration_s, 4.0, 1e-6, "one 4 s heave from the stroke's start")
	assert_eq(engine.state, WinderEngine.State.RUNNING, "caught")
	assert_eq(caught.size(), 1)
	assert_true(s.run.repair.is_done(&"start"), "Start done on the first catch")
	assert_eq(looks, [0, 1, 2] as Array[int], "cold, shuddering at the top, running")
	assert_null(engine.crank, "no crank while it runs")


func test_the_run_up_needs_60_s_of_running() -> void:
	var s: Scenario = make({"seed": 7003, "fixture": E.T.C.scenario_fixture()})
	E.ready(s, RepairList.Kind.STANDARD)
	var engine: WinderEngine = s.run.engine
	engine.state = WinderEngine.State.RUNNING
	engine.caught_at = s.run.tick
	s.step(1199)
	assert_false(engine.run_up_complete(s.run), "59.95 s: not yet")
	s.step(1)
	assert_true(engine.run_up_complete(s.run), "60 s: the clutch may engage")
	assert_almost_eq(engine.running_s(s.run), 60.0, 1e-6)
	# A save keeps the running and its run-up.
	var saved: Dictionary = engine.save_state()
	var other: WinderEngine = WinderEngine.new()
	other.load_state(s.run, saved)
	assert_eq(other.state, WinderEngine.State.RUNNING)
	assert_almost_eq(other.running_s(s.run), 60.0, 1e-6)
	assert_eq(other.fixtures.size(), 3, "the prime, the crank and the throttle")
	assert_eq(other.fixtures, engine.fixtures, "the same fixtures, not new ones")
