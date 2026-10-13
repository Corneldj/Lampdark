extends "res://tests/scenario/kit/scenario_test.gd"
## LFT-02 (GDD §15.8): in a public run, a miner opens the west gate, lets go and steps into the
## doorway. The auto-close comes due while she stands there and waits; a teammate's lever jams;
## the gate shuts on the first tick she is clear of the doorway, and never while any part of her
## overlaps it.

const C = preload("res://tests/scenario/basecamp/camp_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_waits_for_the_doorway_to_clear() -> void:
	var s: Scenario = make({"seed": 81, "fixture": C.scenario_fixture(), "mode": ServerConfig.Mode.PUBLIC})
	var camp: BaseCampState = C.load_camp(s)
	var gs: GateSystem = camp.gate_system
	var west: Gate = gs.gate("west")
	var ann: MinerHandle = s.add_miner("ann", C.lever(s, "west", "inside"))
	var bob: MinerHandle = s.add_miner("bob", C.lever(s, "west", "outside"))
	s.step(2)
	ann.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 30)
	s.step(35)
	assert_true(west.open)
	var opened: int = west.opened_tick
	ann.walk_to(west.middle())
	var radius: float = Tuning.f(&"movement.body_radius")
	var shut_on_body: Array[bool] = [false]
	var shut_at: Array[int] = [-1]
	var overlapping_last: Array[int] = [-1]
	s.on_tick = func(sc: Scenario) -> void:
		var p: Vector2 = sc.run.registry.get_entity(ann.entity_id).position
		var over: bool = west.overlaps(p, radius)
		if over:
			overlapping_last[0] = sc.run.tick - 1
		if not west.open and shut_at[0] < 0:
			shut_at[0] = sc.run.tick - 1
			shut_on_body[0] = over
	s.step(400)
	assert_gte(s.run.tick - 1 - opened, 400, "the auto-close is due")
	assert_true(west.open, "it waits while she stands in the doorway")
	assert_true(west.overlaps(s.run.registry.get_entity(ann.entity_id).position, radius))
	var jams: Array[int] = []
	gs.jammed.connect(func(_side: String) -> void: jams.append(s.run.tick))
	bob.at(s.run.tick).hold(InputRecord.HOLD_INTERACT, 31)
	s.step(40)
	assert_eq(jams.size(), 1, "bob's lever jams")
	assert_true(west.open)
	var clangs: int = C.clangs(s).size()
	assert_eq(clangs, 1, "only the opening clanged")
	ann.walk_to(west.middle() - west.outward * 3)
	s.step(60)
	assert_false(west.open, "clear: it swings shut")
	assert_false(shut_on_body[0], "never shut on her")
	assert_eq(shut_at[0], overlapping_last[0] + 1, "on the first clear tick")
	assert_eq(C.clangs(s).size(), 2)
