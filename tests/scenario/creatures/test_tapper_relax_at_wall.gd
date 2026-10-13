extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-09: in a relax Patrol -> Approach is blocked, but a Tapper resting at a wall strikes a noisy
## miner within reach (a consequence, not a chosen hunt; the cap still binds); a relax ends
## Approach, Listen and Search.

const W = preload("res://tests/scenario/creatures/hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	W.ring(1)


func after_each() -> void:
	super.after_each()
	Tuning.clear_dev_overrides()


func test_relax() -> void:
	var s: Scenario = make({"seed": 110, "fixture": W.road()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(10, 5))
	var bob: MinerHandle = s.add_miner("bob", Vector2i(14, 5))
	var t: Tapper = W.tapper(s, Vector2i(10, 4))
	t.follower.stop()
	s.run.creatures.gate.relax_active = func() -> bool: return true
	s.step(3)
	W.talk(s, bob)
	s.step(3)
	assert_ne(t.state.name, &"approach", "the relax blocks the chosen Approach")
	W.talk(s, ann)
	W.until_state(s, t, &"pin", 40)
	assert_eq(t.state.name, &"pin", "but a noisy miner within reach of its wall is struck")


func test_relax_ends_approach() -> void:
	var s: Scenario = make({"seed": 111, "fixture": W.road()})
	var bob: MinerHandle = s.add_miner("bob", Vector2i(14, 5))
	var t: Tapper = W.tapper(s, Vector2i(10, 8))
	var relax: Array[bool] = [false]
	s.run.creatures.gate.relax_active = func() -> bool: return relax[0]
	s.step(3)
	W.talk(s, bob)
	W.until_state(s, t, &"approach", 10)
	assert_eq(t.state.name, &"approach")
	relax[0] = true
	s.step(2)
	assert_eq(t.state.name, &"patrol", "the relax ends the Approach")
	assert_false(s.run.creatures.gate.is_hunting(t))
