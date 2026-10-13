extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-09: a pin of 500 ticks leaves the victim unconscious at the wall's foot, the lamp falling
## at the wall (MNR-06's hook); only one pin at a time.

const W = preload("res://tests/scenario/creatures/hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	W.ring(1)


func after_each() -> void:
	super.after_each()
	Tuning.clear_dev_overrides()


func test_runs_out() -> void:
	var s: Scenario = make({"seed": 70, "fixture": W.road()})
	var r: Array = W.pinned(s)
	var ann: MinerHandle = r[0]
	var t: Tapper = r[1]
	var dropped: Array[Array] = []
	t.drop_lamp = func(victim: int, face: Vector2i) -> void: dropped.append([victim, face])
	var bob: MinerHandle = s.add_miner("bob", Vector2i(9, 5))
	var g: GrabHold = s.run.holds.grab_of(ann.entity_id)
	for i: int in 10:
		s.step(40)
		W.talk(s, bob)
	s.step(110)
	assert_eq(g.outcome, GrabHold.Outcome.TIMED_OUT)
	assert_eq(W.life(s, ann.entity_id), MinerTransitions.Life.UNCONSCIOUS, "fallen at the wall's foot")
	assert_eq(dropped, [[ann.entity_id, Vector2i(10, 4)]], "the lamp falls at the wall")
	assert_eq(s.run.holds.grab_of(bob.entity_id), null, "one pin at a time: Bob, talking in reach, was never struck during it")
