extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-02's pool: 120 ticks of running from full, 200 to refill from empty, 40 from 2 s, no
## restart until a fresh press, and no running under a carry, aim, Caught or Grabbed stub.

const W = preload("res://tests/unit/mnr/stamina_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _setup() -> Array:
	var s: Scenario = make({"seed": 70, "fixture": W.road()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	return [s, ann]


func test_a_full_pool_runs_120_ticks() -> void:
	var setup: Array = _setup()
	var s: Scenario = setup[0]
	var ann: MinerHandle = setup[1]
	var gaits: Array[int] = W.track(s, ann.slot)
	ann.at(0).move(0.0, InputRecord.Gait.RUN, 200)
	s.step(200)
	assert_eq(W.count_run(gaits), 120, "6.0 s at run speed")
	var first_walk: int = gaits.find(MinerMotion.WALK, gaits.find(MinerMotion.RUN))
	assert_eq(gaits.slice(first_walk, 190).filter(func(g: int) -> bool: return g != MinerMotion.WALK).size(), 0, "then walking")


func test_empty_refills_in_200_ticks_at_any_slower_gait() -> void:
	for gait: InputRecord.Gait in [InputRecord.Gait.WALK, InputRecord.Gait.CROUCH]:
		var setup: Array = _setup()
		var s: Scenario = setup[0]
		var ann: MinerHandle = setup[1]
		s.step(1)
		var st: Stamina = s.run.movement.miner(ann.slot).stamina
		st.pool_ms = 0
		ann.at(1).move(0.0, gait, 400)
		s.step(199)
		assert_lt(st.pool_ms, 6000)
		s.step(1)
		assert_eq(st.pool_ms, 6000, "10 s of %s: full" % InputRecord.Gait.find_key(gait))
	var standing: Array = _setup()
	var t: Scenario = standing[0]
	var bob: MinerHandle = standing[1]
	t.step(1)
	t.run.movement.miner(bob.slot).stamina.pool_ms = 0
	t.step(200)
	assert_eq(t.run.movement.miner(bob.slot).stamina.pool_ms, 6000, "standing still too")


func test_two_seconds_left_runs_40_ticks() -> void:
	var setup: Array = _setup()
	var s: Scenario = setup[0]
	var ann: MinerHandle = setup[1]
	var gaits: Array[int] = W.track(s, ann.slot)
	ann.at(3).move(0.0, InputRecord.Gait.RUN, 100)
	s.step(4)  # ticks 0-3: the first running input applies at tick 4 (one tick of buffer depth)
	assert_eq(W.count_run(gaits), 0)
	s.run.movement.miner(ann.slot).stamina.pool_ms = 2000
	s.step(100)
	assert_eq(W.count_run(gaits), 40, "2 s left: exactly 40 ticks")


func test_no_restart_until_a_fresh_press() -> void:
	var setup: Array = _setup()
	var s: Scenario = setup[0]
	var ann: MinerHandle = setup[1]
	var gaits: Array[int] = W.track(s, ann.slot)
	ann.at(0).move(0.0, InputRecord.Gait.RUN, 300)  # held through exhaustion and refilling
	s.step(300)
	assert_eq(W.count_run(gaits), 120, "never stutters back into a run while held")
	gaits.clear()
	ann.at(300).move(0.0, InputRecord.Gait.WALK, 1).move(0.0, InputRecord.Gait.RUN, 20)  # a fresh press
	s.step(25)
	assert_gt(W.count_run(gaits), 10, "a fresh press runs again")


func test_constraint_stubs_refuse_running_and_the_pool_refills() -> void:
	for owner: StringName in [&"carrying", &"aiming", &"caught", &"grabbed"]:
		var setup: Array = _setup()
		var s: Scenario = setup[0]
		var ann: MinerHandle = setup[1]
		s.step(1)
		var no_run: MinerMotion.Constraints = MinerMotion.Constraints.new()
		no_run.run_allowed = false
		s.run.movement.set_constraint(ann.slot, owner, no_run)
		s.run.movement.miner(ann.slot).stamina.pool_ms = 1000
		var gaits: Array[int] = W.track(s, ann.slot)
		ann.at(1).move(0.0, InputRecord.Gait.RUN, 40)
		s.step(40)
		assert_eq(W.count_run(gaits), 0, "%s: no running" % owner)
		assert_gt(s.run.movement.miner(ann.slot).stamina.pool_ms, 1000, "%s: the pool refills" % owner)
