extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-03: a miner one tile away in the dark is never in the seen set; found only by feeling.

const W = preload("res://tests/scenario/vis/vis_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_body_at_the_elbow_in_the_dark() -> void:
	var s: Scenario = make({"seed": 1, "fixture": FixtureMap.from_ascii(PackedStringArray(["#######", "#ab...#", "#######"]))})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var bob: MinerHandle = s.add_miner("bob", s.fixture.spot("b"), {"facing_deg": 180.0})
	s.step(3)
	var frame: Dictionary = s.run.vision.frame_for(ann.slot)
	assert_eq(W.tiles(frame).size(), 0, "no light: nothing at all")
	assert_eq(W.token_count(frame), 0)
	assert_eq(W.identified(frame).size(), 0, "Bob, one tile away, is not seen")
	assert_eq(s.run.vision.native.unseen_reason(ann.slot, bob.entity_id), LbVision.UNSEEN_DARK)
	# A glimmer below 0.12 on Bob's tile changes nothing.
	s.run.light.grid.add_spot(0, s.fixture.spot("b"), 0.11, 0)
	s.step()
	assert_eq(W.identified(s.run.vision.frame_for(ann.slot)).size(), 0)
	assert_eq(W.token_count(s.run.vision.frame_for(ann.slot)), 0)
