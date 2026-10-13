extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-02's panting: four 9 np events at 0, 2, 4 and 6 s after any run, none after 8 s, moving or
## still; a new run ends it; the voice-loss flag; breath-hold; the fallen never pant.

const W = preload("res://tests/unit/mnr/stamina_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _run_then(s: Scenario, ann: MinerHandle, run_ticks: int, after_gait: InputRecord.Gait) -> int:
	ann.at(0).move(0.0, InputRecord.Gait.RUN, run_ticks)
	if after_gait != InputRecord.Gait.RUN:
		ann.inputs.move(0.0, after_gait, 300)
	var end: Array[int] = [-1]
	s.run.movement.run_ended.connect(func(_slot: int) -> void:
		if end[0] < 0:
			end[0] = s.run.tick)
	s.step(run_ticks + 220)
	return end[0]


func test_four_events_after_any_run_moving_or_still() -> void:
	for case: Array in [[10, InputRecord.Gait.WALK], [60, InputRecord.Gait.CROUCH], [3, InputRecord.Gait.WALK]]:
		var s: Scenario = make({"seed": 71, "fixture": W.road()})
		var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
		var run_ticks: int = case[0]
		var after: InputRecord.Gait = int(Variants.number(case[1])) as InputRecord.Gait
		var end: int = _run_then(s, ann, run_ticks, after)
		var pants: Array = W.pants(s)
		var offsets: Array = pants.map(func(e: NoiseSystem.Event) -> int: return e.tick - end)
		assert_eq(offsets, [0, 40, 80, 120], "a %d-tick run: panting at 0, 2, 4 and 6 s" % run_ticks)
		var first: NoiseSystem.Event = pants[0]
		assert_eq(first.level_np, 9.0)
	var still: Scenario = make({"seed": 72, "fixture": W.road()})
	var bob: MinerHandle = still.add_miner("bob", still.fixture.spot("a"))
	bob.at(0).move(0.0, InputRecord.Gait.RUN, 10)  # then stands still
	still.step(250)
	assert_eq(W.pants(still).size(), 4, "standing still too, and none after 8 s")


func test_a_new_run_ends_it_and_the_next_end_restarts_it() -> void:
	var s: Scenario = make({"seed": 73, "fixture": W.road(120)})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	ann.at(0).move(0.0, InputRecord.Gait.RUN, 10).move(0.0, InputRecord.Gait.WALK, 50).move(0.0, InputRecord.Gait.RUN, 10)
	s.step(300)
	var ticks: Array = W.pants(s).map(func(e: NoiseSystem.Event) -> int: return e.tick)
	assert_eq(ticks.size(), 6, "two events from the first panting, then a full four after the second run")
	var t: Array[int] = []
	for v: Variant in ticks:
		t.append(int(Variants.number(v)))
	assert_eq([t[3] - t[2], t[4] - t[2], t[5] - t[2]], [40, 80, 120], "a fresh 8 s after the second run")


func test_the_voice_loss_flag() -> void:
	var s: Scenario = make({"seed": 74, "fixture": W.road()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var log: Array[Array] = []
	s.on_tick = func(sc: Scenario) -> void:
		log.append([sc.run.movement.is_running(ann.slot), sc.run.movement.is_panting(ann.slot), sc.run.movement.voice_loss_flag(ann.slot)])
	ann.at(0).move(0.0, InputRecord.Gait.RUN, 20)
	s.step(220)
	var running_or_panting: int = 0
	for row: Array in log:
		var flag: bool = row[2]
		var expected: bool = Variants.flag(row[0]) or Variants.flag(row[1])
		assert_eq(flag, expected)
		running_or_panting += 1 if flag else 0
	assert_gt(running_or_panting, 170, "true through the run and its 8 s of panting")
	var last: Array = log[log.size() - 1]
	assert_false(Variants.flag(last[2]), "and false after")


func test_breath_hold_suppresses_events_and_the_timer_runs_on() -> void:
	var s: Scenario = make({"seed": 75, "fixture": W.road()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	ann.at(0).move(0.0, InputRecord.Gait.RUN, 10)
	s.step(14)
	s.run.movement.set_breath_hold(ann.slot, true)
	s.step(150)
	assert_eq(W.pants(s).size(), 1, "only the event before the hold")
	s.run.movement.set_breath_hold(ann.slot, false)
	s.step(20)
	assert_false(s.run.movement.is_panting(ann.slot), "the 8 s ran out under the hold")


func test_the_fallen_never_pant() -> void:
	var s: Scenario = make({"seed": 76, "fixture": W.road()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	ann.at(0).move(0.0, InputRecord.Gait.RUN, 10)
	s.step(15)
	s.run.miner_state.fall_unconscious(ann.entity_id, "smother")
	s.step(200)
	assert_eq(W.pants(s).size(), 1, "panting stops at the fall")
	assert_false(s.run.movement.is_panting(ann.slot))
	s.run.movement.miner(ann.slot).stamina.pool_ms = 0
	s.run.miner_state.revive(ann.entity_id, &"kit")
	s.step(3)
	assert_gt(s.run.movement.miner(ann.slot).stamina.pool_ms, 5900, "revived rested")
