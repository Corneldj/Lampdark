extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-01: no timer runs on the fallen. A body left for 60 minutes of run time is still
## unconscious, and nothing has scheduled its end. In a crew: alone, RSC-09's one self-revive is the
## exception (Gameplay §11.11), so a teammate stands by.

const W = preload("res://tests/unit/mnr/belt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_sixty_minutes() -> void:
	var s: Scenario = make({"seed": 1, "fixture": W.room()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var bob: MinerHandle = s.add_miner("bob", s.fixture.spot("b"))
	bob.brain = null
	s.step(1)
	s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.BLACKDAMP)
	var changes: Array[int] = []
	s.run.miner_state.state_changed.connect(func(e: int, _o: int, _n: int, _c: String) -> void: changes.append(e))
	s.step(1)
	var started: int = Time.get_ticks_msec()
	# The server alone, an hour of ticks (her client's inputs simply stop: input_starved).
	for _i: int in roundi(60.0 * 60.0 * Tuning.f(&"net.tick_hz")):
		s.run.run_tick()
	assert_eq(s.run.miner_state.life(ann.entity_id), MinerTransitions.Life.UNCONSCIOUS, "still unconscious after an hour")
	assert_eq(changes.size(), 1, "the fall was the only change: nothing ended it")
	assert_not_null(s.run.falls.body_of(ann.entity_id))
	gut.p("60 minutes of run time in %d ms" % (Time.get_ticks_msec() - started))
