extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-01 (scn_together_corner): round a corner the path, not the distance, decides; a shut
## gate parts two miners until it opens.

const ROWS: PackedStringArray = [
	"###########",
	"#a...G.b..#",
	"###########",
]


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_shut_gate_parts_them() -> void:
	var s: Scenario = make({"seed": 32, "fixture": FixtureMap.from_ascii(ROWS)})
	var a: MinerHandle = s.add_miner("a", s.fixture.spot("a"))
	var b: MinerHandle = s.add_miner("b", s.fixture.spot("b"))
	s.step()
	assert_false(s.run.movement.together(a.slot, b.slot), "the gate is shut")
	s.set_gate(1, true)
	s.step()
	assert_true(s.run.movement.together(a.slot, b.slot), "6 tiles through the open gate")
