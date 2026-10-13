extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-08: at Pull 35 it attends that miner and holds 15-40 tiles off; below 30 it patrols again.
## With M1's default Pull of 0 it never attends.

const T = preload("res://tests/scenario/creatures/tapper_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_attend() -> void:
	var s: Scenario = make({"seed": 29, "fixture": T.block()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("c"))
	var t: Tapper = T.tapper(s, Vector2i(55, 10))
	s.step(20)
	assert_eq(t.state.name, &"patrol", "Pull 0: never attends")
	var pull: Array[int] = [35]
	s.run.creatures.gate.pull_of = func(e: int) -> int: return pull[0] if e == ann.entity_id else 0
	s.step(300)
	assert_eq(t.state.name, &"attend")
	assert_eq(t.attending, ann.entity_id)
	var d: float = t.position(s.run).distance_to(s.run.registry.get_entity(ann.entity_id).position)
	gut.p("attending from %.1f tiles" % d)
	assert_between(d, 15.0, 40.0, "held 15-40 tiles off")
	assert_eq(s.run.creatures.log.of_type(&"tell").size(), 0, "no hunting taps")
	pull[0] = 25
	s.step(2)
	assert_eq(t.state.name, &"patrol", "below 30: Patrol again")
