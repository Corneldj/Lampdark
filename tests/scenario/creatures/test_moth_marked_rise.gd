extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-03: during a build, a miner at Pull 50 within 80 tiles of the roost raises it to Prowl;
## in a relax, or at 81 tiles, it stays asleep. With no Pull (M1's default) it never fires.

const W = preload("res://tests/scenario/creatures/moth_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _case(distance: float, build: bool, relax: bool, pull: int) -> StringName:
	var s: Scenario = make({"seed": 19, "fixture": W.road()})
	var m: Moth = W.moth(s)
	var miner: SimEntity = s.run.registry.create(WorldIds.EntityKind.MINER, Vector2(W.ROOST) + Vector2(0.5 + distance, 0.5))
	var gate: HuntGate = s.run.creatures.gate
	gate.build_active = func() -> bool: return build
	gate.relax_active = func() -> bool: return relax
	gate.pull_of = func(e: int) -> int: return pull if e == miner.id else 0
	s.step(45)
	return m.state.name


func test_marked() -> void:
	assert_eq(_case(80.0, true, false, 50), &"prowl", "Pull 50 at 80 tiles in a build")
	assert_eq(_case(81.0, true, false, 50), &"asleep", "81 tiles")
	assert_eq(_case(80.0, true, true, 50), &"asleep", "a relax")
	assert_eq(_case(80.0, false, false, 50), &"asleep", "no build")
	assert_eq(_case(10.0, true, false, 49), &"asleep", "Pull 49")
	assert_eq(_case(10.0, true, false, 0), &"asleep", "M1: no Pull")
