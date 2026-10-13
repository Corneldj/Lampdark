extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-09: a flare on the arm frees the victim; the revolver's threshold on the arm frees them and
## the Tapper retreats for 2,400 ticks without taps or hearing; the arm is the only part hit.

const W = preload("res://tests/scenario/creatures/hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	W.ring(1)


func after_each() -> void:
	super.after_each()
	Tuning.clear_dev_overrides()


func test_flare_on_the_arm() -> void:
	var s: Scenario = make({"seed": 130, "fixture": W.road()})
	var r: Array = W.pinned(s)
	var ann: MinerHandle = r[0]
	var t: Tapper = r[1]
	assert_ne(t.hunt.arm, 0, "the arm is out while it pins")
	var arm_at: Vector2 = s.run.registry.get_entity(t.hunt.arm).position
	s.run.light.grid.add_point("flare", 2, 0, 0, 4.0, 1.0, arm_at, 100)
	s.step(3)
	assert_eq(W.life(s, ann.entity_id), MinerTransitions.Life.UPRIGHT, "a flare on the arm frees her")
	assert_eq(t.hunt.arm, 0, "the arm withdraws")


func test_revolver_threshold() -> void:
	var s: Scenario = make({"seed": 131, "fixture": W.road()})
	var r: Array = W.pinned(s)
	var ann: MinerHandle = r[0]
	var t: Tapper = r[1]
	var arm: int = t.hunt.arm
	assert_gt(s.run.creatures.body_radius_of(s.run.registry.get_entity(arm)), 0.0, "the arm is a body")
	assert_eq(s.run.creatures.body_radius_of(s.run.registry.get_entity(t.entity_id)), 0.0, "the Tapper in the rock never is")
	assert_true(s.run.creatures.on_hit(s.run, arm, true))
	s.step(2)
	assert_eq(W.life(s, ann.entity_id), MinerTransitions.Life.UPRIGHT, "the arm lets go")
	var m: MinerStateSystem.Miner = s.run.miner_state.miner(ann.entity_id)
	assert_true(m.overlays.rock_touched(s.run.tick), "freed: rock-touched")
	assert_eq(t.state.name, &"retreat")
	var taps_before: int = s.run.creatures.log.of_type(&"tapper_taps").size()
	for i: int in 20:
		W.talk(s, ann)
		s.step(100)
	assert_eq(s.run.creatures.log.of_type(&"tapper_taps").size(), taps_before, "no taps")
	assert_true(t.heat.is_cold() or t.state.name == &"retreat", "deaf")
	assert_eq(t.state.name, &"retreat", "still retreating at 2,000 ticks")
	s.step(420)
	assert_ne(t.state.name, &"retreat", "over after 2,400 ticks")
