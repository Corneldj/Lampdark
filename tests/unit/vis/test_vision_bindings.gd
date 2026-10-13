extends GutTest
## VIS-03's binding and system: the perception table loads from data, a frame has the agreed
## shape, and nothing in a token can name an entity.

const Scenario = preload("res://tests/scenario/kit/scenario.gd")
const FixtureMap = preload("res://tests/scenario/kit/fixture_map.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_constants() -> void:
	assert_eq([LbVision.SIZE_MINER, LbVision.SIZE_LARGE, LbVision.SIZE_LARGE_MOTIONLESS, LbVision.SIZE_SMALL], [1, 2, 3, 4])
	assert_eq([LbVision.LEVEL_NONE, LbVision.LEVEL_TOKEN, LbVision.LEVEL_IDENTITY], [0, 1, 2])
	assert_eq(LbVision.UNSEEN_DARK, 1)
	assert_eq(SimEntity.FLAG_MOTIONLESS, 1)


func test_every_class_names_a_kind() -> void:
	var doc: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string(VisionSystem.CLASSES)))
	var classes: Dictionary = Variants.dict(doc["classes"])
	for name: Variant in classes.keys():
		assert_true(WorldIds.EntityKind.has(str(name)), "%s is an entity kind" % name)
	for name: String in ["MINER", "STYTHE", "MOTH", "COAT_HEAP", "BESS", "ITEM", "TRAP"]:
		assert_true(classes.has(name), "%s is classified" % name)
	assert_eq(str(Variants.dict(classes["COAT_HEAP"])["size"]), "large")
	assert_eq(str(Variants.dict(classes["ITEM"])["size"]), "small")


func test_a_frame_has_the_agreed_shape() -> void:
	var s: Scenario = Scenario.create({"seed": 4, "fixture": FixtureMap.from_ascii(PackedStringArray(["##########", "#a.......#", "##########"]))})
	var ann: RefCounted = s.add_miner("ann", s.fixture.spot("a"))
	s.run.light.grid.add_spot(0, Vector2i(4, 1), 0.2, 0)
	var shape: SimEntity = s.run.registry.create(WorldIds.EntityKind.MINER, Vector2(4.5, 1.5))
	s.step(2)
	var slot: int = ann.get(&"slot")
	var frame: Dictionary = s.run.vision.frame_for(slot)
	assert_eq(frame.keys().size(), 8)
	for key: String in ["tiles", "tokens", "identified", "glow_present", "glow_colour", "margin_tiles", "margin_tokens", "blinded"]:
		assert_true(frame.has(key), key)
	var tokens: Dictionary = frame["tokens"]
	assert_eq(tokens.keys(), ["size", "position"], "a token is a size class and a position, nothing else")
	var sizes: PackedByteArray = tokens["size"]
	assert_eq(sizes, PackedByteArray([LbVision.SIZE_MINER]), "the fringe miner is a token")
	var identified: PackedInt64Array = frame["identified"]
	assert_false(identified.has(shape.id))
	var glow: PackedByteArray = frame["glow_present"]
	assert_eq(glow.size(), 22, "22 buckets of 5 degrees across 110")
	s.close()
