extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-02: a kit use takes exactly 100 ticks (rescue.kit_use_s) standing still holding interact;
## releasing at 4.9 s, moving, or the target being lifted off the table cancels it, kit unspent.

const C = preload("res://tests/scenario/basecamp/camp_world.gd")
const M = preload("res://tests/unit/rescue/medbay_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _setup(run_seed: int) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": C.scenario_fixture()})
	var camp: BaseCampState = C.load_camp(s)
	var table: Vector2i = camp.medbay_tables()[0]
	var spot: Vector2i = M.beside(s, table)
	var ann: MinerHandle = s.add_miner("ann", spot)
	var bob: MinerHandle = s.add_miner("bob", spot)
	s.step(1)
	M.give_kit(s, ann.entity_id)
	assert_true(s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.BLAST))
	s.step(2)
	M.lay(s, bob.entity_id, table)
	s.step(1)
	return [s, ann, bob, table]


func test_exactly_100_ticks() -> void:
	var parts: Array = _setup(1)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var bob: MinerHandle = parts[2]
	var a: TimedAction = M.start(s, ann, bob.entity_id, KitUse.Mode.REVIVE, 120)
	assert_eq(a.ticks_needed, 100, "5 s at 20 Hz")
	s.step(99)
	assert_eq(M.life(s, bob.entity_id), MinerTransitions.Life.UNCONSCIOUS, "99 ticks: not yet")
	assert_eq(M.kits(s, ann.entity_id), 1)
	s.step(1)
	assert_true(a.done)
	assert_eq(M.kits(s, ann.entity_id), 0, "spent at the 100th tick")
	s.step(1)
	assert_eq(M.life(s, bob.entity_id), MinerTransitions.Life.UPRIGHT, "up")


func test_release_at_4_9_s_spends_nothing() -> void:
	var parts: Array = _setup(2)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var bob: MinerHandle = parts[2]
	M.start(s, ann, bob.entity_id, KitUse.Mode.REVIVE, 99)
	s.step(110)
	assert_eq(M.life(s, bob.entity_id), MinerTransitions.Life.UNCONSCIOUS)
	assert_eq(M.kits(s, ann.entity_id), 1, "kit unspent")


func test_moving_cancels() -> void:
	var parts: Array = _setup(3)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var bob: MinerHandle = parts[2]
	var a: TimedAction = M.start(s, ann, bob.entity_id, KitUse.Mode.REVIVE, 120)
	var reasons: Array[StringName] = []
	a.cancelled.connect(func(_a: TimedAction, r: StringName) -> void: reasons.append(r))
	s.step(40)
	ann.at(s.run.tick).move(90.0, InputRecord.Gait.WALK, 2)
	s.step(80)
	assert_eq(reasons, [TimedAction.MOVED] as Array[StringName])
	assert_eq(M.life(s, bob.entity_id), MinerTransitions.Life.UNCONSCIOUS)
	assert_eq(M.kits(s, ann.entity_id), 1)


func test_lifting_the_target_cancels() -> void:
	var parts: Array = _setup(4)
	var s: Scenario = parts[0]
	var ann: MinerHandle = parts[1]
	var bob: MinerHandle = parts[2]
	var table: Vector2i = parts[3]
	var cat: MinerHandle = s.add_miner("cat", M.beside(s, table))
	s.step(1)
	var a: TimedAction = M.start(s, ann, bob.entity_id, KitUse.Mode.REVIVE, 120)
	var reasons: Array[StringName] = []
	a.cancelled.connect(func(_a: TimedAction, r: StringName) -> void: reasons.append(r))
	cat.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 42)
	s.step(1)
	assert_true(s.run.inventory.start_action(s.run, s.run.carry.lift_action(s.run, cat.entity_id, bob.entity_id)))
	s.step(60)
	assert_true(s.run.carry.is_carrying(cat.entity_id), "Cat lifted Bob off the table")
	assert_eq(reasons, [TimedAction.TARGET] as Array[StringName], "the use cancels")
	assert_eq(M.kits(s, ann.entity_id), 1, "kit unspent")
