extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-01's together helper: 6 tiles by path or less; a pillar can make neighbours alone.

const ROWS: PackedStringArray = [
	"##################",
	"#a.....b.c.......#",
	"#................#",
	"######d##########",
	"#....#...........#",
	"#....#e..........#",
	"#....#...........#",
	"#....#...........#",
	"##################",
]


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_six_by_path_is_together_seven_is_not() -> void:
	var s: Scenario = make({"seed": 8, "fixture": FixtureMap.from_ascii(ROWS)})
	var a: MinerHandle = s.add_miner("a", s.fixture.spot("a"))
	var b: MinerHandle = s.add_miner("b", s.fixture.spot("b"))
	var c: MinerHandle = s.add_miner("c", s.fixture.spot("c"))
	s.step()
	assert_true(s.run.movement.together(a.slot, b.slot), "6 tiles")
	assert_false(s.run.movement.together(a.slot, c.slot), "8 tiles")
	assert_true(s.run.movement.together(b.slot, a.slot), "pairwise both ways")


func test_round_a_pillar() -> void:
	var s: Scenario = make({"seed": 9, "fixture": FixtureMap.from_ascii(ROWS)})
	var d: MinerHandle = s.add_miner("d", s.fixture.spot("d"))
	var e: MinerHandle = s.add_miner("e", s.fixture.spot("e"))
	s.step()
	var straight: float = (Vector2(s.fixture.spot("d")) - Vector2(s.fixture.spot("e"))).length()
	assert_lt(straight, 3.0)
	assert_true(s.run.movement.together(d.slot, e.slot), "the doorway joins them")
	var f: MinerHandle = s.add_miner("f", Vector2i(4, 5))
	var g: MinerHandle = s.add_miner("g", Vector2i(7, 5))
	s.step()
	assert_false(s.run.movement.together(f.slot, g.slot), "3 tiles apart through the rock, 9 or more by path")


func test_pace_queries() -> void:
	var s: Scenario = make({"seed": 10, "fixture": FixtureMap.from_ascii(ROWS)})
	var a: MinerHandle = s.add_miner("a", s.fixture.spot("a"))
	s.step()
	assert_true(s.run.movement.is_still(a.slot))
	a.at(1).move(0.0, InputRecord.Gait.CROUCH, 4).move(0.0, InputRecord.Gait.WALK, 4)
	s.step(4)
	assert_false(s.run.movement.is_still(a.slot))
	assert_true(s.run.movement.at_crouch_pace_or_slower(a.slot), "1.5 tiles/s is a crouch's pace")
	s.step(4)
	assert_false(s.run.movement.at_crouch_pace_or_slower(a.slot), "3.0 is not")
