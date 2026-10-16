extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-09's solo wipe, through LFT-11's hook: while a self-revive is pending deferral_active() is
## true (a wipe waits for it); a fall alone with the self-revive spent fires `wiped` that tick.

const LW = preload("res://tests/unit/rescue/lone_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_the_wipe_waits_for_a_pending_self_revive() -> void:
	var w: Array = LW.crew(make, 911, ["ann"])
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1][0]
	assert_false(s.run.self_revive.deferral_active())
	LW.fall(s, ann)
	assert_true(s.run.self_revive.deferral_active(), "pending: LFT-11 waits")
	s.step(610)
	assert_false(s.run.self_revive.deferral_active(), "spent: nothing to wait for")


func test_a_fall_alone_with_it_spent_wipes_that_tick() -> void:
	var w: Array = LW.crew(make, 912, ["ann"])
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1][0]
	LW.fall(s, ann)
	s.step(610)
	var wiped_at: Array[int] = []
	s.run.self_revive.wiped.connect(func(_m: int, t: int) -> void: wiped_at.append(t))
	assert_true(s.run.falls.fall_unconscious(s.run, ann.entity_id, FallCause.Cause.ROOF_FALL))
	var before: int = s.run.tick
	s.step(1)
	assert_eq(wiped_at, [before] as Array[int], "the tick of the fall")
	assert_false(s.run.self_revive.deferral_active())
