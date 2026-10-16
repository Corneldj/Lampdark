extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-09 in Night Shift: a smothered miner comes round where they lie exactly 600 ticks after the
## fall, Upright and Hurt; a second fall in the run is the wipe on that tick; a kit only cures.

const LW = preload("res://tests/unit/rescue/lone_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_smothered_alone_she_comes_round_at_six_hundred_ticks() -> void:
	var w: Array = LW.crew(make, 931, ["ann"], ServerConfig.Mode.NIGHTSHIFT)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1][0]
	assert_true(AloneRules.is_solo(s.run.crew), "Night Shift is solo")
	assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.MOTH_SMOTHER))
	s.step(1)
	var rec: Dictionary = s.run.falls.journal[s.run.falls.journal.size() - 1]
	var fell_tick: int = int(Variants.number(rec["tick"]))
	var at: Vector2i = s.run.registry.get_entity(ann.entity_id).tile()
	var up_at: int = -1
	for _i: int in 620:
		s.step(1)
		if up_at < 0 and LW.life(s, ann) == MinerTransitions.Life.UPRIGHT:
			up_at = s.run.tick - 1
	gut.p("fell at %d, up at %d" % [fell_tick, up_at])
	assert_eq(up_at - fell_tick, 600, "exactly 600 ticks")
	assert_true(LW.hurt(s, ann), "Hurt")
	assert_eq(s.run.registry.get_entity(ann.entity_id).tile(), at, "where she lay")
	var wipes: Array[int] = []
	s.run.self_revive.wiped.connect(func(_m: int, t: int) -> void: wipes.append(t))
	assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.MOTH_SMOTHER))
	var second: int = s.run.tick
	s.step(1)
	assert_eq(wipes, [second] as Array[int], "the second fall is a wipe on that tick")


func test_a_kit_only_cures_in_night_shift() -> void:
	var w: Array = LW.crew(make, 932, ["ann"], ServerConfig.Mode.NIGHTSHIFT)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1][0]
	LW.fall(s, ann)
	assert_false(s.run.revival.may_revive(s.run, ann.entity_id, ann.entity_id), "never herself")
	var bess: SimEntity = s.run.registry.create(WorldIds.EntityKind.MINER, Vector2(4.5, 2.5))
	assert_false(s.run.revival.may_revive(s.run, bess.id, ann.entity_id), "and in Night Shift a kit never revives anyone")
