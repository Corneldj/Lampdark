extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-09 (Gameplay §7.2): a viewer within moth.tell_reach_tiles (20) of an awake or stirring Moth
## gets the dust flag; at 21 tiles none; a sleeping Moth gives none. The flag rides the frame.

const FW = preload("res://tests/scenario/vis/flame_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_twenty_tiles_and_asleep() -> void:
	var s: Scenario = make({"seed": 91, "fixture": FW.hall(60)})
	var near: MinerHandle = s.add_miner("near", Vector2i(16, 2))
	var far: MinerHandle = s.add_miner("far", Vector2i(2, 4))
	s.step(1)
	s.place_creature(WorldIds.EntityKind.MOTH, Vector2i(31, 2))
	var m: Moth = s.run.creatures.creature_of_kind(WorldIds.EntityKind.MOTH)
	s.step(4)
	assert_false(s.run.tells.dust_for(near.slot), "asleep: no dust")
	assert_false(near.connection.view.dust)
	m.waker = {}
	m.enter(s.run, &"prowl", "test")
	m.awake.begin(s.run, m, false)
	s.step(1)
	var mp: Vector2 = m.position(s.run)
	for h: MinerHandle in [near, far]:
		var at: Vector2 = s.run.registry.get_entity(h.entity_id).position
		assert_eq(s.run.tells.dust_for(h.slot), at.distance_to(mp) <= 20.0, "%s at %.2f tiles" % [h.name, at.distance_to(mp)])
	assert_true(s.run.tells.dust_for(near.slot), "near (within 20) gets dust")
	assert_false(s.run.tells.dust_for(far.slot), "far (beyond 20) gets none")
	s.step(3)
	assert_true(near.connection.view.dust, "the flag rides the frame")
	assert_false(far.connection.view.dust)
