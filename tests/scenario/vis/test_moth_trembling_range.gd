extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-08 with CRT-04: an awake Moth trembles a lamp lying 20 tiles off and not one 21 tiles off; a
## watcher sees it on the lamp's record. A sleeping Moth trembles nothing.

const FW = preload("res://tests/scenario/vis/flame_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_twenty_tiles_not_twenty_one() -> void:
	var s: Scenario = make({"seed": 62, "fixture": FW.hall(60)})
	var obs: MinerHandle = s.add_miner("obs", Vector2i(2, 3), {"facing_deg": 0.0})
	obs.at(0).face(0.0)
	s.step(1)
	var near: GauzeLamp = FW.lamp(s, Vector2i(6, 2))
	var far: GauzeLamp = FW.lamp(s, Vector2i(5, 4))
	s.place_creature(WorldIds.EntityKind.MOTH, Vector2i(26, 2))
	var m: Moth = s.run.creatures.creature_of_kind(WorldIds.EntityKind.MOTH)
	s.step(6)
	assert_eq(s.run.flame_states.flags_of(near.source), 0, "asleep: nothing")
	var near_at: Vector2 = Vector2(6.5, 2.5)
	var on_wire: Array[Dictionary] = FW.near(obs.connection.view, near_at)
	assert_eq(on_wire.size(), 1, "the watcher sees the lamp")
	assert_eq(int(Variants.number(on_wire[0].get("flame", 0))), 0)
	m.waker = {}
	m.enter(s.run, &"prowl", "test")
	m.awake.begin(s.run, m, false)
	s.step(1)
	var mp: Vector2 = m.position(s.run)
	assert_eq((s.run.flame_states.flags_of(near.source) & FlameFlags.TREMBLE) != 0, mp.distance_to(near_at) <= 20.0,
		"near lamp at %.2f tiles" % mp.distance_to(near_at))
	assert_eq((s.run.flame_states.flags_of(far.source) & FlameFlags.TREMBLE) != 0, mp.distance_to(Vector2(5.5, 4.5)) <= 20.0,
		"far lamp at %.2f tiles" % mp.distance_to(Vector2(5.5, 4.5)))
	s.step(2)
	on_wire = FW.near(obs.connection.view, near_at)
	assert_eq(int(Variants.number(on_wire[0].get("flame", 0))) & FlameFlags.TREMBLE, FlameFlags.TREMBLE, "the watcher sees it tremble")
