extends GutTest
## The per-tick change feed: systems append during the tick; stage 16 reads it; it then clears.

const Systems = preload("res://tests/support/sim_test_systems.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_record_stage_sees_this_ticks_changes_in_order() -> void:
	var run: RunState = RunState.create(3, ServerConfig.Mode.FRIENDS, false)
	var inputs: Dictionary = {0: [["spawn", 1, 1], ["spawn", 2, 2]], 1: [["despawn", 0]]}
	run.add_system(Systems.ScriptedInputs.new(inputs))
	run.add_system(Systems.Wander.new())
	var tap: Systems.FeedTap = Systems.FeedTap.new()
	run.add_system(tap)
	run.run_tick()
	var kinds: Array[int] = []
	for change: ChangeFeed.Change in tap.seen:
		kinds.append(change.kind)
		assert_eq(change.tick, 0)
	assert_eq(kinds, [ChangeFeed.Kind.ENTITY_CREATED, ChangeFeed.Kind.ENTITY_CREATED,
		ChangeFeed.Kind.ENTITY_MOVED, ChangeFeed.Kind.ENTITY_MOVED] as Array[int])
	tap.seen.clear()
	run.run_tick()
	assert_eq(tap.seen[0].kind, ChangeFeed.Kind.ENTITY_DESTROYED, "tick 1 starts with a fresh feed")
	assert_eq(tap.seen[0].tick, 1)
