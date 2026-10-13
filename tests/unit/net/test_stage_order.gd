extends GutTest
## Stages run in the declared order every tick; undeclared or clashing systems fail at start-up.

const Systems = preload("res://tests/support/sim_test_systems.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_systems_run_in_stage_then_order() -> void:
	var run: RunState = RunState.create(1, ServerConfig.Mode.FRIENDS, false)
	var log: PackedStringArray = PackedStringArray()
	var pairs: Array[Vector2i] = [Vector2i(14, 0), Vector2i(3, 5), Vector2i(1, 0), Vector2i(16, 2),
		Vector2i(3, 1), Vector2i(12, 0), Vector2i(7, 9), Vector2i(7, 2), Vector2i(16, 0), Vector2i(6, 0)]
	for pair: Vector2i in pairs:
		assert_true(run.add_system(Systems.Recording.new(pair.x, pair.y, log)))
	var expected: PackedStringArray = PackedStringArray(["1.0", "3.1", "3.5", "6.0", "7.2", "7.9", "12.0", "14.0", "16.0", "16.2"])
	for tick: int in 3:
		log.clear()
		run.run_tick()
		assert_eq(log, expected, "tick %d order" % tick)
	assert_eq(run.tick, 3)


func test_undeclared_system_fails() -> void:
	var run: RunState = RunState.create(1, ServerConfig.Mode.FRIENDS, false)
	assert_false(run.add_system(Systems.Undeclared.new()))
	assert_push_error("declares no valid stage")
	assert_eq(run.startup_errors().size(), 1)


func test_duplicate_stage_and_order_fails() -> void:
	var run: RunState = RunState.create(1, ServerConfig.Mode.FRIENDS, false)
	var log: PackedStringArray = PackedStringArray()
	assert_true(run.add_system(Systems.Recording.new(7, 1, log)))
	assert_false(run.add_system(Systems.Recording.new(7, 1, log)))
	assert_push_error("both declare stage 7 order 1")


func test_illusions_run_after_deltas_and_before_send() -> void:
	assert_lt(StageTable.Stage.DELTAS, StageTable.Stage.ILLUSIONS)
	assert_lt(StageTable.Stage.ILLUSIONS, StageTable.Stage.SEND)
	assert_lt(StageTable.Stage.MINERS, StageTable.Stage.LIGHT_PASS_1)
	assert_lt(StageTable.Stage.LIGHT_PASS_1, StageTable.Stage.CREATURES)


func test_mirror_is_pushed_before_the_light_stage() -> void:
	var run: RunState = RunState.create(1, ServerConfig.Mode.FRIENDS, false)
	run.registry.create(WorldIds.EntityKind.MINER, Vector2(3.5, -2.0))
	run.run_tick()
	assert_eq(LbEntityMirror.mirrored_tick(), 0)
	assert_eq(LbEntityMirror.count(), 1)
	var mirrored: Dictionary = LbEntityMirror.find(1)
	assert_eq(int(Variants.number(mirrored.get("kind", -1))), WorldIds.EntityKind.MINER)
	assert_almost_eq(Variants.number(mirrored.get("x", 0.0)), 3.5, 0.0001)
