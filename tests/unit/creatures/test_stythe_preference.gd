extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-13: of two eligible miners the Stythe prefers the longer unheard, and on a tie the higher Pull.

const W = preload("res://tests/unit/creatures/stythe_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_longest_unheard_then_pull() -> void:
	var s: Scenario = make({"seed": 1211, "fixture": W.road(60), "overrides": W.ON})
	var st: StytheCreature = W.stythe(s, Vector2i(30, 2))
	var ann: MinerHandle = W.miner(s, "ann", Vector2i(29, 2))
	var bob: MinerHandle = W.miner(s, "bob", Vector2i(31, 2))
	s.step(1)
	s.run.creatures.set_frozen(s.run, true)  # preference alone: no hunt (CRT-14) acts on it
	s.step(1)
	assert_eq(StytheEligibility.ranked(s.run, st).size(), 2, "both within reach")
	assert_eq(st.best_target(s.run), ann.entity_id, "a tie on both: the lower id")
	W.pull(st, {bob.entity_id: 30.0})
	assert_eq(st.best_target(s.run), bob.entity_id, "equal silence: the higher Pull")
	s.step(40)
	s.run.heard.mark_heard(bob.slot, &"voice")
	s.step(2)
	assert_eq(st.best_target(s.run), ann.entity_id, "the longer unheard first, whatever the Pull")
