extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-16: a shot at a Tapper's arm with a pinned miner between takes the miner: the first body on
## the line, seen or not, in the dark.

const R = preload("res://tests/unit/mnr/revolver_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_the_body_between_takes_it() -> void:
	var s: Scenario = make({"seed": 1261, "fixture": R.hall()})
	var ann: MinerHandle = R.miner(s, "ann", Vector2i(3, 2))
	var bob: MinerHandle = R.miner(s, "bob", Vector2i(11, 2), 0.0)
	var arm: int = s.run.registry.create(WorldIds.EntityKind.TAPPER_ARM, Vector2(12.2, 2.5)).id
	s.step(2)
	s.run.miner_state.enter_grabbed(bob.entity_id, &"pin", arm)
	s.step(2)
	R.armed(s, ann)
	R.aim(s, ann)
	s.step(3)
	R.trigger(s, ann, 0.0)
	s.step(8)
	var shot: Dictionary = s.run.revolver.shots[0]
	assert_eq(int(Variants.number(shot["hit"])), bob.entity_id, "the pinned miner, unseen in the dark, takes the shot")
	assert_eq(StringName(str(shot["outcome"])), &"friendly_hit")
	assert_true(s.run.registry.has(arm))
