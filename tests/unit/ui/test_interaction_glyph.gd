extends GutTest
## UI-01: the interaction glyph shows the bound key and the verb on the nearest identified thing within
## vision.touch_range_tiles (1.5) that has a verb (shared/interaction_verbs.gd, the server's table
## too); never on a shape token, never in the Dark, never while a wheel or the ring is up.

const W = preload("res://tests/unit/ui/inplay_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_client())


func test_touch_range_and_verbs() -> void:
	assert_almost_eq(Tuning.f(&"vision.touch_range_tiles"), 1.5, 1e-6)
	var v: ReceivedView = W.view(Vector2(10, 10))
	W.identity(v, 1, SeenKind.Kind.ITEM, Vector2(11.4, 10.0))
	var pick: Dictionary = InteractionGlyph.pick(v, 1.5)
	assert_eq(int(Variants.number(pick["token"])), 1)
	assert_eq(str(pick["verb_key"]), "verb.pick_up")
	v.entities[1]["position"] = Vector2(11.6, 10.0)
	assert_eq(InteractionGlyph.pick(v, 1.5), {}, "beyond 1.5 tiles: none")


func test_each_kind_its_verb() -> void:
	assert_eq(InteractionVerbs.for_seen(SeenKind.Kind.ITEM), "verb.pick_up")
	assert_eq(InteractionVerbs.for_seen(SeenKind.Kind.PHONE), "verb.crank")
	assert_eq(InteractionVerbs.for_seen(SeenKind.Kind.MINER), "verb.ring", "a standing miner: the hands ring")
	assert_eq(InteractionVerbs.for_seen(SeenKind.Kind.MINER, MinerCues.LYING_BREATHING), "verb.lift")
	assert_eq(InteractionVerbs.for_seen(SeenKind.Kind.MINER, MinerCues.LYING_STILL), "verb.lift")
	for kind: int in [SeenKind.Kind.STYTHE, SeenKind.Kind.MOTH, SeenKind.Kind.BESS, SeenKind.Kind.TAPPER, SeenKind.Kind.TRAP,
			SeenKind.Kind.COAT_HEAP, SeenKind.Kind.UNKNOWN]:
		assert_eq(InteractionVerbs.for_seen(kind), "", "no verb: no glyph (%d)" % kind)
	# LFT-06's tank and LFT-08's engine: the fixture's kind, as the glyph reads its held field.
	var fixture: int = SeenKind.Kind.FIXTURE
	assert_eq(InteractionVerbs.for_seen(fixture, 0, FixtureKinds.tank_glass(4, 9) & 0x3F), "verb.pour")
	assert_eq(InteractionVerbs.for_seen(fixture, 0, FixtureKinds.Kind.ENGINE_PRIME), "verb.prime")
	for look: int in FixtureKinds.Look.values():
		assert_eq(InteractionVerbs.for_seen(fixture, 0, FixtureKinds.engine(look) & 0x3F), "verb.crank", "the crank, whatever the winder's look")
	assert_eq(InteractionVerbs.for_seen(fixture, 0, FixtureKinds.Kind.ENGINE_THROTTLE), "verb.throttle")
	assert_eq(InteractionVerbs.for_seen(fixture, 0, FixtureKinds.Kind.CAGE_CORD), "verb.pull_cord", "LFT-10's cord: 'Pull'")
	for look: int in FixtureKinds.CageLook.values():
		assert_eq(InteractionVerbs.for_seen(fixture, 0, FixtureKinds.cage(look) & 0x3F), "", "the cage itself: no glyph")
	assert_eq(InteractionVerbs.for_seen(fixture, 0, FixtureKinds.Kind.NONE), "", "an unknown fixture: no glyph")


func test_never_on_a_token_and_the_nearest_wins() -> void:
	var v: ReceivedView = W.view(Vector2(10, 10))
	W.token(v, 5, SeenKind.Size.MINER, Vector2(10.5, 10.0))
	W.token(v, 6, SeenKind.Size.SMALL, Vector2(10.0, 10.5))
	assert_eq(InteractionGlyph.pick(v, 1.5), {}, "tokens carry no kind: never a glyph")
	W.identity(v, 7, SeenKind.Kind.MOTH, Vector2(10.2, 10.0))
	W.identity(v, 8, SeenKind.Kind.PHONE, Vector2(11.0, 10.0))
	W.identity(v, 9, SeenKind.Kind.ITEM, Vector2(10.0, 11.2))
	assert_eq(int(Variants.number(InteractionGlyph.pick(v, 1.5)["token"])), 8, "the nearest with a verb (the moth has none)")


func test_the_layer_shows_key_and_verb_at_the_thing() -> void:
	var l: InPlayLayer = InPlayLayer.new()
	add_child_autofree(l)
	for family: String in ["kbm", "pad"]:
		var r: InputRouter = InputRouter.new(null, family)
		var v: ReceivedView = W.view(Vector2(10, 10))
		W.identity(v, 1, SeenKind.Kind.ITEM, Vector2(11, 10))
		l.update(W.frame(v, r))
		var tile_px: float = Tuning.f(&"camera.tile_px_at_1080p")
		assert_true(l.glyph.visible)
		assert_eq(l.glyph.verb_key, "verb.pick_up")
		assert_eq(l.glyph.key_label, "%s %s" % [UiText.text("glyph.hold"), GlyphText.label(r.store, "interact", family)],
			"Hold and the bound key for %s (picking up is held)" % family)
		assert_ne(l.glyph.key_label, "")
		assert_almost_eq(l.glyph.position.x, 11.0 * tile_px, 0.01, "at the thing, not the miner")
		assert_true(r.target_in_reach, "pad A interacts rather than sets down")
		l.update(W.frame(v, r, {"black": true}))
		assert_false(l.glyph.visible, "the Dark: nothing")
		assert_false(r.target_in_reach)
	var pad_key: String = GlyphText.label(InputRouter.new(null, "pad").store, "interact", "pad")
	assert_ne(pad_key, GlyphText.label(InputRouter.new().store, "interact", "kbm"), "glyphs follow the active controller")


func test_hidden_while_picking() -> void:
	var l: InPlayLayer = InPlayLayer.new()
	add_child_autofree(l)
	var r: InputRouter = InputRouter.new()
	r.know_ring({"open": true, "options": ["hand_over"]})
	var v: ReceivedView = W.view(Vector2(10, 10))
	W.identity(v, 1, SeenKind.Kind.ITEM, Vector2(11, 10))
	l.update(W.frame(v, r))
	assert_false(l.glyph.visible)
	assert_true(l.ring.visible, "the ring instead")
	assert_eq(l.ring.slices, ["ring.hand_over"] as Array[String])


func test_the_server_reads_the_same_table() -> void:
	var src: String = FileAccess.get_file_as_string("res://server/systems/feel/feel_system.gd")
	assert_true(src.contains("InteractionVerbs.for_seen("), "VIS-07's feel verb is the glyph's")
