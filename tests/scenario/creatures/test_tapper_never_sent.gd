extends "res://tests/scenario/kit/scenario_test.gd"
## CRT-08: the Tapper's position, state, heat map and heard events never reach a client: a miner
## right beside it, with light, gets no record of it, and no client code names them.

const T = preload("res://tests/scenario/creatures/tapper_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_never_in_a_frame() -> void:
	var s: Scenario = make({"seed": 30, "fixture": T.road()})
	var ann: MinerHandle = s.add_miner("ann", Vector2i(3, 2), {"facing_deg": 180.0})
	ann.at(0).face(180.0)
	var t: Tapper = T.tapper(s, Vector2i(2, 1))
	t.follower.stop()
	var lit: Array = []
	for x: int in 8:
		for y: int in 5:
			lit.append(Vector2i(x, y))
	s.run.light.grid.add_area("emergency", 3, 0, 1.0, lit)
	# Set it straight onto the lit floor (as if passing beneath it); not a step the check judges.
	t.max_speed = 100.0
	s.run.registry.move(t.entity_id, Vector2(2.5, 2.5))
	s.step(10)
	for raw: Variant in ann.capture.entities_visible(s.run.tick).values():
		assert_true(false, "a record reached the client: %s" % raw)
	assert_eq(s.run.vision.native.sees_entity(ann.slot, t.entity_id), LbVision.LEVEL_NONE, "never perceived, even on lit floor")


func test_no_client_code_names_it() -> void:
	var pattern: RegEx = RegEx.create_from_string("\\bTapper\\b|HeatMap|TapperHearing|HeardEvent|attending")
	for dir: String in ["res://client", "res://shared/net"]:
		for f: String in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			for line: String in FileAccess.get_file_as_string(dir.path_join(f)).split("\n"):
				if not line.strip_edges().begins_with("#"):
					assert_null(pattern.search(line), "%s: %s" % [f, line.strip_edges()])
