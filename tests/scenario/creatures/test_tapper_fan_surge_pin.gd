extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-09 (§6.9): in a Fan surge a lure fails and talk does not spoil a pull, but a scream does.

const W = preload("res://tests/scenario/creatures/hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	W.ring(1)


func after_each() -> void:
	super.after_each()
	Tuning.clear_dev_overrides()


func test_surge() -> void:
	var s: Scenario = make({"seed": 100, "fixture": W.road()})
	var r: Array = W.pinned(s)
	var ann: MinerHandle = r[0]
	var t: Tapper = r[1]
	t.hearing.fan_surge = func() -> bool: return true
	var bob: MinerHandle = s.add_miner("bob", Vector2i(11, 5))
	s.step(2)
	W.bang(s, Vector2i(17, 5), 14.0, 0)
	s.step(3)
	assert_eq(W.life(s, ann.entity_id), MinerTransitions.Life.GRABBED, "the lure fails in the surge")
	bob.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 70)
	s.step(5)
	W.talk(s, bob)
	s.step(2)
	assert_eq(s.run.creatures.log.of_type(&"tapper_pull_spoiled").size(), 0, "talk does not spoil it")
	W.talk(s, bob, Tuning.f(&"voice.scream_np"))
	s.step(2)
	assert_eq(s.run.creatures.log.of_type(&"tapper_pull_spoiled").size(), 1, "a scream does")
