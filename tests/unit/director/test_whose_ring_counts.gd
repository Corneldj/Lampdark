extends GutTest
## DIR-04: each "whose ring" helper uses its own entity's tile: a lamp hung in ring 2 while its
## owner stands in ring 1 reports ring 2; a creature in ring 1 reads ring 1 while its target
## stands in ring 2.


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_own_tiles() -> void:
	var run: RunState = RunState.new()
	var centre: Vector2 = Vector2(WorldIds.SHAFT_CENTRE_X2, WorldIds.SHAFT_CENTRE_Y2) / 2.0
	var owner: SimEntity = run.registry.create(WorldIds.EntityKind.MINER, centre + Vector2(150.0, 0.0))
	var lamp: SimEntity = run.registry.create(WorldIds.EntityKind.ITEM, centre + Vector2(250.0, 0.0))
	var tapper: SimEntity = run.registry.create(WorldIds.EntityKind.TAPPER, centre + Vector2(190.0, 0.0))
	var target: SimEntity = run.registry.create(WorldIds.EntityKind.MINER, centre + Vector2(205.0, 0.0))
	assert_eq(Depth.ring_for_miner(run, owner.id), 1)
	assert_eq(Depth.ring_for_lamp(run, lamp.id), 2, "the hung lamp reads its own ring, not its owner's")
	assert_eq(Depth.ring_for_creature(run, tapper.id), 1, "the creature reads its own ring")
	assert_eq(Depth.ring_for_miner(run, target.id), 2, "while its target stands in ring 2")
	assert_eq(Depth.pull_factor(Depth.ring_for_miner(run, target.id)), 1.5)
	var stythe: SimEntity = run.registry.create(WorldIds.EntityKind.STYTHE, centre + Vector2(150.0, 0.0))
	assert_eq(Depth.ring_for_creature(run, stythe.id), 1)
	assert_eq(Depth.unheard_mark_s(run, target.id), 45.0, "the unheard mark: the miner's own ring (2), not the Stythe's (1)")
	assert_eq(Depth.unheard_mark_s(run, owner.id), 60.0)


func test_hot_reload_changes_the_columns() -> void:
	assert_eq(Depth.pull_factor(2), 1.5)
	assert_true(Tuning.set_dev_override("depth.pull_factor", [0.5, 1.0, 1.75, 2.0, 2.5]).is_empty())
	assert_true(Tuning.set_dev_override("depth.relax_s", [60, 60, 50, 30, 30]).is_empty())
	assert_eq(Depth.pull_factor(2), 1.75, "a data edit, no code change")
	assert_eq(Depth.relax_s(2), 50.0)
	Tuning.clear_dev_overrides()
	assert_eq(Depth.pull_factor(2), 1.5)
