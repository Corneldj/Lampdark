extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-03: the blind area is black even where lit, the miner's own lamp included; a teammate
## facing it sees it.

const W = preload("res://tests/scenario/vis/vis_world.gd")
const ROWS: PackedStringArray = [
	"######################",
	"#b.........a.........#",
	"#....................#",
	"######################",
]


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_your_lamp_lights_your_back_for_others() -> void:
	var s: Scenario = make({"seed": 3, "fixture": FixtureMap.from_ascii(ROWS)})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"), {"facing_deg": 0.0})
	var bob: MinerHandle = s.add_miner("bob", s.fixture.spot("b"), {"facing_deg": 0.0})
	ann.at(0).face(0.0)
	bob.at(0).face(0.0)
	W.lamp(s, Vector2(11.5, 1.5), 5.5, ann.entity_id)
	s.step(3)
	var behind: Vector2i = Vector2i(10, 1)
	assert_gte(s.run.light.light_at(behind), 0.75, "the tile just behind Ann, bright in her own lamp's core")
	assert_false(W.tiles(s.run.vision.frame_for(ann.slot)).has(behind), "black to Ann: it is behind her")
	assert_true(W.tiles(s.run.vision.frame_for(bob.slot)).has(behind), "Bob, facing it, sees it")
	for raw: Variant in W.tiles(s.run.vision.frame_for(ann.slot)).keys():
		var t: Vector2i = raw
		assert_true(s.run.vision.native.in_cone(ann.slot, Vector2(t) + Vector2(0.5, 0.5)), "every tile Ann gets is in her cone")
	assert_eq(s.run.vision.native.sees_entity(bob.slot, ann.entity_id), LbVision.LEVEL_IDENTITY, "Bob sees Ann in her own core")
