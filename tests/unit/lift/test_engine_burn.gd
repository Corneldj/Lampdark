extends GutTest
## LFT-08 with LFT-06: running burns one tick of the tank a tick. A full Standard tank runs exactly
## 20 minutes (24,000 ticks) and each can adds 5; the engine stops on the tick the tank empties, its
## run-up reset, with engine_stopped(dry) once.


func before_all() -> void:
	assert_true(Tuning.load_server())


## A run with a Standard list, a tank and an engine already caught (anchors given: no base camp).
func _running(level: int) -> Array:
	var run: RunState = RunState.new()
	run.header.run_seed = 7101
	run.repair = RepairListState.new()
	run.repair.set_list(RepairList.for_run(7101, RepairList.Kind.STANDARD, false))
	run.fuel = FuelTank.new()
	run.fuel.done = true
	run.fuel.level_ticks = level
	var engine: WinderEngine = WinderEngine.new()
	engine.anchors = {"engine_prime": Vector2(4.5, 4.5), "engine_crank": Vector2(6.5, 4.5), "engine_throttle": Vector2(8.5, 4.5)}
	engine.state = WinderEngine.State.RUNNING
	engine.caught_at = 0
	run.engine = engine
	return [run, engine]


## Ticks the engine until it stops; returns the tick it stopped on.
func _run_dry(run: RunState, engine: WinderEngine, top_up_at: int = -1) -> int:
	while engine.is_running():
		run.tick += 1
		if run.tick == top_up_at:
			var can: Item = Item.make(1, ItemKinds.Kind.PARAFFIN_CAN, 1, {"fills": 4.0})
			assert_eq(run.fuel.pour(run, 0, can), 4.0)
		engine.tick(run)
		if run.tick > 100000:
			break
	return run.tick


func test_a_full_standard_tank_runs_exactly_20_minutes() -> void:
	var r: Array = _running(24000)
	var run: RunState = r[0]
	var engine: WinderEngine = r[1]
	var stops: Array[StringName] = []
	engine.engine_stopped.connect(func(why: StringName) -> void: stops.append(why))
	var stopped_at: int = _run_dry(run, engine)
	assert_eq(stopped_at, 20 * 60 * 20, "24,000 ticks from the catch")
	assert_true(run.fuel.is_empty(), "stopped the tick the tank emptied")
	assert_eq(stops, [WinderEngine.DRY] as Array[StringName])
	assert_eq(engine.state, WinderEngine.State.COLD, "a new start needs prime, crank and throttle")
	assert_false(engine.run_up_complete(run), "the run-up reset")
	assert_eq(engine.running_s(run), 0.0)


func test_each_can_poured_while_running_adds_5_minutes() -> void:
	var r: Array = _running(24000)
	var run: RunState = r[0]
	var engine: WinderEngine = r[1]
	var stopped_at: int = _run_dry(run, engine, 12000)
	assert_eq(stopped_at, 25 * 60 * 20, "20 minutes, and 5 for the can")
