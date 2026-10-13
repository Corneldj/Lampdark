extends "res://tests/scenario/kit/scenario_test.gd"
## RSC-03: a relax starting mid-grab or mid-trap changes no elapsed count and releases no hold; a
## victim whose player disconnects stays held and the hold runs on; no relax hook reaches a hold
## (static scan).

const H = preload("res://tests/scenario/rescue/hold_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_relax() -> void:
	var s: Scenario = make({"seed": 10, "fixture": H.hall()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var bob: MinerHandle = s.add_miner("bob", s.fixture.spot("b"))
	s.step(1)
	var id: int = s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.TAPPER_PIN, 99, 500)
	s.run.holds.catch(s.run, bob.entity_id, CaughtHold.Kind.STAPLE_PIT, 9)
	s.step(50)
	s.run.creatures.gate.relax_active = func() -> bool: return true
	s.step(50)
	var g: GrabHold = s.run.holds.grabs[id]
	assert_eq(g.elapsed, 100, "the count ran through the relax")
	assert_true(s.run.holds.is_held(ann.entity_id))
	assert_true(s.run.holds.is_held(bob.entity_id))


func test_disconnect() -> void:
	var s: Scenario = make({"seed": 11, "fixture": H.hall()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.step(1)
	var id: int = s.run.holds.grab(s.run, ann.entity_id, GrabHold.Kind.TAPPER_PIN, 99, 500)
	s.step(20)
	ann.at(s.run.tick).disconnect_at()
	s.step(80)
	var g: GrabHold = s.run.holds.grabs[id]
	assert_eq(g.elapsed, 100, "the hold runs on after the drop")
	assert_eq(H.life(s, ann.entity_id), MinerTransitions.Life.GRABBED)


func test_no_relax_code_touches_holds() -> void:
	for f: String in ["holds.gd", "grab_hold.gd", "caught_hold.gd", "self_rescue.gd"]:
		var text: String = FileAccess.get_file_as_string("res://server/systems/rescue/" + f)
		for line: String in text.split("\n"):
			if not line.strip_edges().begins_with("#"):
				assert_false(line.contains("relax"), "%s reads the relax: %s" % [f, line.strip_edges()])
