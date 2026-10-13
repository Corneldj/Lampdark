extends GutTest
## CRT-01's guard registry: a predicate per creature, none is an error, and any_holds_near looks
## at the miner and everyone within 10 tiles.

const StubCreature = preload("res://tests/scenario/kit/kit_creature.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_registering_without_a_predicate_is_an_error() -> void:
	var g: GuardRegistry = GuardRegistry.new()
	assert_false(g.register(WorldIds.EntityKind.MOTH, Callable()))
	assert_push_error("without a guard predicate")
	var sys: CreatureSystem = CreatureSystem.new()
	var run: RunState = RunState.new()
	var c: StubCreature = StubCreature.new(WorldIds.EntityKind.MOTH)
	c.with_guard = false
	assert_eq(sys.spawn(run, c, Vector2i(4, 4)), ERR_INVALID_PARAMETER, "a creature without one is refused")
	assert_push_error("without a guard predicate")


func test_any_holds_near() -> void:
	var run: RunState = RunState.new()
	var g: GuardRegistry = GuardRegistry.new()
	var ann: SimEntity = run.registry.create(WorldIds.EntityKind.MINER, Vector2(0.0, 0.0))
	var bob: SimEntity = run.registry.create(WorldIds.EntityKind.MINER, Vector2(9.0, 0.0))
	var cid: SimEntity = run.registry.create(WorldIds.EntityKind.MINER, Vector2(30.0, 0.0))
	g.register(WorldIds.EntityKind.TAPPER, func(_r: RunState, miner: int) -> bool: return miner == bob.id)
	assert_true(g.holds(run, WorldIds.EntityKind.TAPPER, bob.id))
	assert_false(g.holds(run, WorldIds.EntityKind.TAPPER, ann.id))
	assert_false(g.holds(run, WorldIds.EntityKind.MOTH, bob.id), "no predicate, no hold")
	assert_true(g.any_holds_near(run, ann.id), "Bob, 9 tiles off, is guarded: so is Ann's neighbourhood")
	assert_true(g.any_holds_near(run, bob.id))
	assert_false(g.any_holds_near(run, cid.id), "nobody within 10 tiles of Cid is guarded")
	g.register(WorldIds.EntityKind.MOTH, func(_r: RunState, miner: int) -> bool: return miner == cid.id)
	assert_true(g.any_holds_near(run, cid.id), "any creature's predicate counts")
