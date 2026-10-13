extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-09: speech spoils a pull; if the victim is still pinned when the ReStrike falls due, the
## Tapper stays in Pin; a ReStrike on a victim who has walked off misses and the grab is abandoned.

const W = preload("res://tests/scenario/creatures/hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	W.ring(1)


func after_each() -> void:
	super.after_each()
	Tuning.clear_dev_overrides()


func test_still_pinned_stays_in_pin() -> void:
	var s: Scenario = make({"seed": 80, "fixture": W.road()})
	var r: Array = W.pinned(s)
	var ann: MinerHandle = r[0]
	var t: Tapper = r[1]
	var bob: MinerHandle = s.add_miner("bob", Vector2i(11, 5))
	s.step(2)
	bob.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 20)
	s.step(5)
	W.talk(s, bob)
	s.step(120)
	assert_eq(t.state.name, &"pin", "still pinned when the ReStrike fell due: it stays in Pin")
	assert_eq(W.life(s, ann.entity_id), MinerTransitions.Life.GRABBED)


func test_restrike_misses_a_victim_who_left() -> void:
	var s: Scenario = make({"seed": 81, "fixture": W.road()})
	var r: Array = W.pinned(s)
	var ann: MinerHandle = r[0]
	var bob: MinerHandle = s.add_miner("bob", Vector2i(11, 5))
	s.step(2)
	var g: GrabHold = s.run.holds.grab_of(ann.entity_id)
	bob.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 70)
	s.step(5)
	W.talk(s, bob)
	s.step(65)
	assert_eq(W.life(s, ann.entity_id), MinerTransitions.Life.UPRIGHT)
	ann.at(s.run.tick).move(0.0, InputRecord.Gait.RUN, 20)
	s.step(60)
	assert_eq(g.outcome, GrabHold.Outcome.ABANDONED, "she was beyond reach when it came due")
	assert_ne(W.life(s, ann.entity_id), MinerTransitions.Life.GRABBED)
