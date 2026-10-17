extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-09 (Gameplay §3.6, §10.7): a dry engine does not put the pit back to sleep. Started for real,
## the engine wakes the Moth; run dry, it stops and the Moth still prowls for the gates; fuelled and
## started again it catches, and the apex, latched once, is not begun again; the cage leaving ends it
## and the Moth no longer prowls for the engine.

const A = preload("res://tests/scenario/apex/apex_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_it_holds_through_a_dry_engine_and_clears_when_the_cage_leaves() -> void:
	var s: Scenario = make({"seed": 9601, "fixture": A.E.T.C.scenario_fixture(), "overrides": A.ON})
	var gate: Gate = A.world(s, 140)
	var m: Moth = A.moth(s, A.on_road(gate, 120))
	s.step(3)
	var caught: int = A.start_engine(s)
	var apex: ApexController = s.run.apex
	var engine: WinderEngine = s.run.engine
	assert_true(apex.active)
	assert_eq(apex.started_tick, caught)
	assert_true(s.run_until(func(_sc: Scenario) -> bool: return m.state.name == &"prowl", 60))
	# Dry.
	s.run.fuel.level_ticks = 20
	assert_true(s.run_until(func(_sc: Scenario) -> bool: return not engine.is_running(), 60), "it ran dry")
	s.step(100)
	assert_true(apex.active, "the pit stays awake")
	assert_eq(m.rose_for, "engine", "the Moth still prowls for the gates")
	# Fuelled and started again: the apex is not begun again.
	s.run.fuel.level_ticks = FuelTank.unit_ticks()
	var ann: MinerHandle = s.miners[0]
	var bob: MinerHandle = s.miners[1]
	A.E.move_to(s, ann, "engine_prime")
	A.E.prime(s, ann)
	A.E.move_to(s, ann, "engine_crank")
	A.E.hold(s, ann, 200)
	assert_true(A.E.throttle_after_cue(s, bob, 0.5))
	assert_true(engine.is_running(), "caught again")
	assert_eq(apex.started_tick, caught, "latched once")
	var begun: int = 0
	for e: Dictionary in s.run.creatures.log.entries:
		begun += 1 if e["type"] == &"apex_started" else 0
	assert_eq(begun, 1)
	# The cage leaves.
	apex.cage_departed(s.run)
	assert_false(apex.active)
	assert_ne(m.rose_for, "engine", "the Moth no longer prowls for the engine")
	assert_false(Variants.flag(s.run.creatures.gate.apex_on.call()))
