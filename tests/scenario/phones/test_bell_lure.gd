extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-12 with CRT-09 (Gameplay §6.6, §7.3): the operator ringing a live phone 8 tiles from a
## Tapper's pin is a loud lure (its 20 np bell): the arm goes to the bell, and the victim is free.
## Ringing a dead line does nothing, and the pin holds.

const W = preload("res://tests/scenario/creatures/hunt_world.gd")
const P = preload("res://tests/unit/phones/phone_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func before_each() -> void:
	W.ring(1)


func after_each() -> void:
	super.after_each()
	Tuning.clear_dev_overrides()


func _ring_beside_a_pin(run_seed: int, live: bool) -> int:
	var s: Scenario = make({"seed": run_seed, "fixture": W.road()})
	var r: Array = W.pinned(s)
	var ann: MinerHandle = r[0]
	assert_eq(W.life(s, ann.entity_id), MinerTransitions.Life.GRABBED, "pinned")
	P.power(s, live)
	var p: PitPhone = P.phone(s, "p1", Vector2i(18, 5))
	s.step(2)
	assert_eq(s.run.phones.ring(s.run, p.number, 0), live)
	s.step(3)
	return W.life(s, ann.entity_id)


func test_a_bell_eight_tiles_off_draws_the_arm() -> void:
	assert_eq(_ring_beside_a_pin(4801, true), MinerTransitions.Life.UPRIGHT, "a live phone's bell lures the arm off her")
	assert_eq(_ring_beside_a_pin(4802, false), MinerTransitions.Life.GRABBED, "a dead line rings nothing: still pinned")
