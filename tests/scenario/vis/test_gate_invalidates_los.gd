extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-03: opening or shutting a gate changes line of sight in the same tick.

const W = preload("res://tests/scenario/vis/vis_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_gate_opens_and_shuts_the_view() -> void:
	var s: Scenario = make({"seed": 6, "fixture": FixtureMap.from_ascii(PackedStringArray(["##############", "#a....G......#", "##############"]))})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	s.run.light.grid.add_area("test", 1, 0, 0.6, [Vector2i(8, 1), Vector2i(9, 1), Vector2i(10, 1)])
	s.step(2)
	var beyond: Vector2i = Vector2i(9, 1)
	assert_false(W.tiles(s.run.vision.frame_for(ann.slot)).has(beyond), "behind the shut gate")
	var recasts: int = s.run.vision.native.recasts()
	assert_true(s.set_gate(1, true))
	s.step()
	assert_true(W.tiles(s.run.vision.frame_for(ann.slot)).has(beyond), "open: seen in the same tick")
	assert_eq(s.run.vision.native.recasts(), recasts + 1, "one recast, caused by the gate")
	assert_true(s.set_gate(1, false))
	s.step()
	assert_false(W.tiles(s.run.vision.frame_for(ann.slot)).has(beyond), "shut again")
	s.step(5)
	assert_eq(s.run.vision.native.recasts(), recasts + 2, "otherwise the field stays cached")
