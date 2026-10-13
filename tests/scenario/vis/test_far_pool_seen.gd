extends "res://tests/scenario/kit/scenario_test.gd"
## VIS-03: a far teammate's pool is seen at any distance in sight: at 25 tiles it is still sent;
## beyond the detail region it arrives as edge glow, and nothing comes from beyond 40 tiles.

const W = preload("res://tests/scenario/vis/vis_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_a_pool_25_tiles_down_the_road() -> void:
	var row: String = "#a" + ".".repeat(56) + "#"
	var s: Scenario = make({"seed": 5, "fixture": FixtureMap.from_ascii(PackedStringArray(["#".repeat(59), row, "#".repeat(59)]))})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	var bob_entity: SimEntity = s.run.registry.create(WorldIds.EntityKind.MINER, Vector2(25.5, 1.5))
	W.lamp(s, Vector2(25.5, 1.5), 4.0, bob_entity.id)
	s.step(2)
	var frame: Dictionary = s.run.vision.frame_for(ann.slot)
	var seen: Dictionary = W.tiles(frame)
	assert_true(seen.has(Vector2i(25, 1)), "the pool 24 tiles away is detail")
	assert_true(W.identified(frame).has(bob_entity.id), "and Bob, in his own core, is identified")
	var lit_far: Array = []
	for x: int in range(30, 58):
		if s.run.light.light_at(Vector2i(x, 1)) >= 0.12:
			lit_far.append(x)
	s.run.registry.move(bob_entity.id, Vector2(36.5, 1.5))
	W.lamp(s, Vector2(36.5, 1.5), 4.0, 0)
	s.step(2)
	frame = s.run.vision.frame_for(ann.slot)
	seen = W.tiles(frame)
	assert_false(seen.has(Vector2i(36, 1)), "35 tiles away: beyond the detail region")
	var glow: PackedByteArray = frame["glow_present"]
	assert_true(glow.has(1), "but it glows at the edge")
	W.lamp(s, Vector2(50.5, 1.5), 4.0, 0)
	s.step(2)
	for raw: Variant in W.tiles(s.run.vision.frame_for(ann.slot)).keys():
		var t: Vector2i = raw
		assert_lte(t.x, 41, "nothing beyond 40 tiles")
