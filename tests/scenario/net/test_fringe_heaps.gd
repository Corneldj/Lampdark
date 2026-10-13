extends "res://tests/scenario/kit/scenario_test.gd"
## NET-04: the Moth asleep among three heaps of coats in the fringe: four records identical but
## for their tokens.

const N = preload("res://tests/scenario/net/net04_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_four_identical_records() -> void:
	var s: Scenario = make({"seed": 48, "fixture": N.road()})
	var ann: MinerHandle = s.add_miner("ann", s.fixture.spot("a"))
	for x: int in [6, 8, 10, 12]:
		s.run.light.grid.add_spot(0, Vector2i(x, 2), 0.2, 0)
	for x: int in [6, 8, 12]:
		s.run.registry.create(WorldIds.EntityKind.COAT_HEAP, Vector2(x + 0.5, 2.5))
	s.run.registry.create(WorldIds.EntityKind.MOTH, Vector2(10.5, 2.5), SimEntity.FLAG_MOTIONLESS)
	s.step(3)
	var entities: Dictionary = s.client(ann).entities_visible(2)
	assert_eq(entities.size(), 4)
	var shapes: Dictionary = {}
	for raw: Variant in entities.values():
		var e: Dictionary = raw
		assert_eq(int(Variants.number(e["level"])), 1, "a token, not an identity")
		assert_eq(int(Variants.number(e["size_or_kind"])), SeenKind.Size.LARGE_MOTIONLESS)
		assert_false(e.has("facing"))
		shapes[[e["level"], e["size_or_kind"]]] = true
	assert_eq(shapes.size(), 1, "the four records differ only in token and position")
