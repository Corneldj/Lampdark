extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-07: a body one tile away behind a wall is never felt; feeling finds nothing.

const F = preload("res://tests/unit/vis/feel_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_wall() -> void:
	var rows: PackedStringArray = PackedStringArray(["#######", "#..#..#", "#.a#b.#", "#..#..#", "#######"])
	var s: Scenario = make({"seed": 1, "fixture": FixtureMap.from_ascii(rows)})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var bob: MinerHandle = s.add_miner("bob", s.fixture.spot("b"))
	s.step(2)
	s.run.falls.fall_unconscious(s.run, bob.entity_id, FallCause.Cause.BLAST)
	s.step(2)
	assert_lte(s.run.registry.get_entity(bob.entity_id).position.distance_to(s.run.registry.get_entity(ann.entity_id).position), 2.0)
	F.feel(s, ann)
	assert_eq(str(ann.connection.feel.last_feel["caption_key"]), "feel.nothing", "the wall between: nothing")
