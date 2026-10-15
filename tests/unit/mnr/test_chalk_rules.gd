extends "res://tests/scenario/kit/scenario_test.gd"
## MNR-10: placement on a rib face within reach ahead, else the floor; floor arrows along the facing
## in 45-degree steps, rib arrows along the rib; a new mark replaces the old; refused carrying
## two-handed, Grabbed, unconscious or with the revolver drawn, allowed Caught; No Chalk.

const C = preload("res://tests/unit/mnr/chalk_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _world(run_seed: int, tile: Vector2i, facing: float) -> Array:
	var s: Scenario = make({"seed": run_seed, "fixture": C.B.room()})
	C.B.light(s)
	var ann: MinerHandle = C.miner(s, "ann", tile, facing)
	s.step(3)
	return [s, ann]


func test_rib_face_within_reach_else_the_floor() -> void:
	var w: Array = _world(1011, Vector2i(12, 3), 0.0)  # beside the east wall, facing it
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	C.chalk(s, ann, ChalkMarks.Kind.DIGIT_7)
	assert_gt(C.ticks_to_mark(s, 80), 0)
	assert_ne(s.run.chalk.store.glyph_at(Vector2i(12, 3), ChalkMarks.Surface.EAST), 0, "on the east rib face")
	assert_eq(s.run.chalk.store.glyph_at(Vector2i(12, 3), ChalkMarks.Surface.FLOOR), 0)
	ann.at(s.run.tick).face(180.0)
	s.step(4)
	C.chalk(s, ann, ChalkMarks.Kind.DIGIT_3)
	assert_gt(C.ticks_to_mark(s, 80), 0)
	assert_eq(ChalkMarks.kind_of(s.run.chalk.store.glyph_at(Vector2i(12, 3), ChalkMarks.Surface.FLOOR)), ChalkMarks.Kind.DIGIT_3,
		"facing open floor: on the floor under her")


func test_arrows_floor_quantised_rib_along_the_rib() -> void:
	var w: Array = _world(1012, Vector2i(6, 3), 50.0)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	C.chalk(s, ann, ChalkMarks.Kind.ARROW)
	assert_gt(C.ticks_to_mark(s, 80), 0)
	assert_eq(ChalkMarks.direction_of(s.run.chalk.store.glyph_at(Vector2i(6, 3), ChalkMarks.Surface.FLOOR)), 1, "50 degrees: south-east")
	var w2: Array = _world(1013, Vector2i(6, 1), 280.0)  # the north wall ahead, facing a little east of north
	var s2: Scenario = w2[0]
	var bob: MinerHandle = w2[1]
	C.chalk(s2, bob, ChalkMarks.Kind.ARROW)
	assert_gt(C.ticks_to_mark(s2, 80), 0)
	var g: int = s2.run.chalk.store.glyph_at(Vector2i(6, 1), ChalkMarks.Surface.NORTH)
	assert_ne(g, 0, "on the north rib")
	assert_eq(ChalkMarks.direction_of(g), 0, "along the rib, to the east, nearer the facing")


func test_a_new_mark_replaces_the_old() -> void:
	var w: Array = _world(1014, Vector2i(6, 3), 0.0)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	C.chalk(s, ann, ChalkMarks.Kind.CROSS)
	assert_gt(C.ticks_to_mark(s, 80), 0)
	C.chalk(s, ann, ChalkMarks.Kind.BANG)
	assert_gt(C.ticks_to_mark(s, 80), 0)
	assert_eq(ChalkMarks.kind_of(s.run.chalk.store.glyph_at(Vector2i(6, 3), ChalkMarks.Surface.FLOOR)), ChalkMarks.Kind.BANG)
	assert_eq(s.run.chalk.store.marks.size(), 1, "one mark a surface")


func test_who_may_chalk() -> void:
	var w: Array = _world(1015, Vector2i(6, 3), 0.0)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	var h: HandsAndBelt = s.run.inventory.hands_of(ann.entity_id)
	h.two_handed = true
	assert_eq(s.run.chalk.refusal(s.run, ann.entity_id), "the free hand is not free", "carrying two-handed")
	h.two_handed = false
	h.free_hand = s.run.inventory.world.make(ItemKinds.Kind.REVOLVER)
	assert_eq(s.run.chalk.refusal(s.run, ann.entity_id), "the free hand is not free", "the revolver drawn")
	h.free_hand = null
	s.run.miner_state.enter_caught(ann.entity_id, &"test", 1)
	s.step(2)
	assert_eq(s.run.chalk.refusal(s.run, ann.entity_id), "", "Caught: she may")
	s.run.miner_state.release_caught(ann.entity_id, "test")
	s.step(2)
	s.run.miner_state.enter_grabbed(ann.entity_id, &"test", 99)
	s.step(2)
	assert_eq(s.run.chalk.refusal(s.run, ann.entity_id), "grabbed, unconscious or dead", "Grabbed")
	s.run.miner_state.end_grab(ann.entity_id, false)
	s.step(2)
	assert_eq(s.run.miner_state.life(ann.entity_id), MinerTransitions.Life.UNCONSCIOUS)
	assert_eq(s.run.chalk.refusal(s.run, ann.entity_id), "grabbed, unconscious or dead", "unconscious")


func test_no_chalk_makes_nothing_and_shuts_the_wheel() -> void:
	var w: Array = _world(1016, Vector2i(6, 3), 0.0)
	var s: Scenario = w[0]
	var ann: MinerHandle = w[1]
	s.run.chalk.no_chalk = func() -> bool: return true
	s.run.inventory.hands_of(ann.entity_id).chalk = false
	C.chalk(s, ann, ChalkMarks.Kind.CROSS)
	assert_eq(C.ticks_to_mark(s, 80), -1, "nothing made")
	assert_eq(str(s.run.chalk.refused[s.run.chalk.refused.size() - 1]["why"]), "no chalk")
	var router: InputRouter = InputRouter.new()
	router.know_inventory({"lamp": [0, 0], "hooked": false, "chalk": false, "two_handed": false, "free": [0, 0], "slots": []})
	assert_false(router.has_chalk, "the client knows: its wheel never opens")
