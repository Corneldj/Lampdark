extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-04: a grabbed miner is beyond the Moth until released: at a pinned miner it smothers the
## lamp, never the miner.

const A = preload("res://tests/scenario/creatures/moth_awake_world.gd")
const H = preload("res://tests/scenario/creatures/hunt_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	H.ring(1)


func after_each() -> void:
	super.after_each()
	Tuning.clear_dev_overrides()


func test_pinned() -> void:
	var s: Scenario = make({"seed": 82, "fixture": H.road()})
	var m: Moth = A.awake(s, Vector2i(25, 5), false)
	# The Moth waits out a relax while the Tapper pins ann; then it may commit.
	var relax: Array[bool] = [true]
	s.run.creatures.gate.relax_active = func() -> bool: return relax[0]
	var ann: MinerHandle = A.lit_miner(s, "ann", Vector2i(10, 5))
	var lamp: GauzeLamp = s.run.lamps.lamp_in_hand(ann.entity_id)
	var t: Tapper = H.tapper(s, Vector2i(10, 4))
	t.follower.stop()
	s.step(2)
	H.talk(s, ann)
	H.until_state(s, t, &"pin", 60)
	assert_not_null(s.run.holds.grab_of(ann.entity_id), "pinned")
	relax[0] = false
	assert_gte(A.until_state(s, m, &"linger", 600), 0, "the Moth reached her")
	assert_eq(A.life(s, ann.entity_id), MinerTransitions.Life.GRABBED, "never the pinned miner")
	assert_eq(lamp.state(), GauzeLamp.State.OUT, "only her lamp")
