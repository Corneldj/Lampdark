extends GutTest
## NET-01's SimLoop: fixed step, catch-up cap, overruns, pause rules, freeze, timings.

const Systems = preload("res://tests/support/sim_test_systems.gd")
const TICK: int = 50000

var overrun_count: int = 0


func before_all() -> void:
	assert_true(Tuning.load_server(), "tuning loads")


func _loop(offline: bool = false) -> SimLoop:
	var mode: ServerConfig.Mode = ServerConfig.Mode.NIGHTSHIFT if offline else ServerConfig.Mode.FRIENDS
	var loop: SimLoop = SimLoop.new(RunState.create(7, mode, offline))
	overrun_count = 0
	loop.overrun.connect(func(_late: int, _dropped: int, _worst: int, _stage: String) -> void: overrun_count += 1)
	return loop


func test_reads_tuning() -> void:
	var loop: SimLoop = _loop()
	assert_eq(loop.tick_usec, TICK, "net.tick_hz 20 is a 50 ms tick")
	assert_eq(loop.max_catchup, Tuning.i(&"net.tick_max_catchup"))
	assert_eq(loop.late_threshold_usec, 5000)


func test_fixed_step() -> void:
	var loop: SimLoop = _loop()
	loop.start(0)
	assert_eq(loop.pump(0), 1, "the first tick runs at once")
	assert_eq(loop.pump(TICK - 1), 0)
	assert_eq(loop.pump(TICK), 1)
	assert_eq(loop.pump(2 * TICK + 4000), 1, "4 ms late is not an overrun")
	assert_eq(overrun_count, 0)
	assert_eq(loop.run.tick, 3)
	assert_eq(loop.usec_until_next(2 * TICK + 4000), TICK - 4000)


func test_late_tick_is_an_overrun() -> void:
	var loop: SimLoop = _loop()
	loop.start(0)
	loop.pump(0)
	assert_eq(loop.pump(TICK + 6000), 1)
	assert_eq(overrun_count, 1, "6 ms late is logged")


func test_stall_runs_at_most_the_catchup_cap_and_logs_one_overrun() -> void:
	var loop: SimLoop = _loop()
	loop.start(0)
	loop.pump(0)
	# A 120 ms stall: the tick due at 50 ms is pumped at 170 ms.
	var ran: int = loop.pump(TICK + 120000)
	assert_true(ran <= loop.max_catchup, "ran %d ticks, cap %d" % [ran, loop.max_catchup])
	assert_eq(overrun_count, 1)
	assert_eq(loop.pump(4 * TICK), 1, "back on schedule at once")
	assert_eq(overrun_count, 1, "no spiral of overruns")


func test_long_stall_drops_debt() -> void:
	var loop: SimLoop = _loop()
	loop.start(0)
	loop.pump(0)
	var ran: int = loop.pump(1000000)
	assert_eq(ran, loop.max_catchup)
	assert_eq(overrun_count, 1)
	assert_gt(loop.usec_until_next(1000000), 0, "the remaining debt was dropped")
	assert_eq(loop.pump(1000000), 0)


func test_pause_only_offline() -> void:
	var online: SimLoop = _loop(false)
	online.start(0)
	assert_false(online.pause(), "refused online")
	assert_eq(online.pump(0), 1, "timers run on")
	var offline: SimLoop = _loop(true)
	offline.start(0)
	offline.pump(0)
	assert_true(offline.pause())
	assert_eq(offline.pump(10 * TICK), 0, "nothing runs while paused")
	offline.resume(10 * TICK)
	assert_eq(offline.pump(10 * TICK), 1, "continues from the same tick")
	assert_eq(offline.run.tick, 2)


func test_freeze_keeps_the_network_pumping_and_loses_no_tick() -> void:
	var loop: SimLoop = _loop()
	var network: SimSystem = Systems.Counter.new(StageTable.Stage.RECEIVE)
	var miners: SimSystem = Systems.Counter.new(StageTable.Stage.MINERS)
	loop.run.add_system(network)
	loop.run.add_system(miners)
	loop.start(0)
	loop.pump(0)
	loop.pump(TICK)
	assert_eq(loop.run.tick, 2)
	loop.freeze()
	loop.pump(2 * TICK)
	loop.pump(5 * TICK)
	assert_eq(loop.run.tick, 2, "no tick while frozen")
	assert_eq((miners as Systems.Counter).calls, 2, "simulation systems stand still")
	assert_gt((network as Systems.Counter).calls, 2, "the network stage keeps pumping")
	loop.unfreeze(6 * TICK)
	assert_eq(loop.pump(6 * TICK), 1)
	assert_eq(loop.run.tick, 3, "continues from the same tick, none lost or doubled")
	assert_eq((miners as Systems.Counter).ticks_seen, PackedInt64Array([0, 1, 2]))


func test_timings_per_stage_and_system() -> void:
	var loop: SimLoop = _loop()
	loop.run.add_system(Systems.Counter.new(StageTable.Stage.ROAD_GRAPH))
	loop.step(30)
	var timer: TickTimer = loop.run.timer
	assert_eq(timer.sample_count(TickTimer.TICK), 30)
	for stage: int in range(1, StageTable.STAGE_COUNT + 1):
		assert_true(timer.has(TickTimer.stage_key(stage)), "stage %d timed" % stage)
	assert_true(timer.has("system.11.counter_11"), "systems are timed")
	var tick_summary: Dictionary = timer.summary(TickTimer.TICK)
	assert_has(tick_summary, "p99")
	assert_true(timer.has(TickTimer.stage_key(StageTable.Stage.VISIBILITY)))
	assert_true(timer.has(TickTimer.stage_key(StageTable.Stage.ROAD_GRAPH)))


func test_timer_window_and_percentiles() -> void:
	var timer: TickTimer = TickTimer.new(100)
	for usec: int in range(1, 201):
		timer.record("k", usec)
	assert_eq(timer.sample_count("k"), 100, "only the window is kept")
	assert_eq(timer.percentile("k", 50.0), 150)
	assert_eq(timer.percentile("k", 99.0), 199)
	assert_eq(timer.percentile("k", 100.0), 200)
