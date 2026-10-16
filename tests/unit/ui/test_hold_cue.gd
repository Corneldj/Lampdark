extends GutTest
## The interaction glyph's hold cue: a timed action's verb reads "Hold <key>" and fills a ring while
## interact is held, at the server's time for it; a tap verb (the ring) has neither.


func before_all() -> void:
	assert_true(Tuning.load_client())


func test_a_timed_verb_reads_hold_and_fills() -> void:
	var g: InteractionGlyph = InteractionGlyph.new()
	add_child_autofree(g)
	g.show_on(Vector2(100, 100), "E", "verb.pick_up")
	assert_eq(g.key_label, "Hold E")
	assert_eq(g.hold_fraction, 0.0, "not yet held")
	g.show_on(Vector2(100, 100), "E", "verb.lever", Tuning.f(&"basecamp.gate_lever_s") * 0.5)
	assert_almost_eq(g.hold_fraction, 0.5, 1e-6, "half way through the lever's 1.5 s")
	g.show_on(Vector2(100, 100), "E", "verb.lever", 99.0)
	assert_eq(g.hold_fraction, 1.0)


func test_a_tap_verb_has_no_hold() -> void:
	var g: InteractionGlyph = InteractionGlyph.new()
	add_child_autofree(g)
	g.show_on(Vector2(100, 100), "E", "verb.ring", 1.0)
	assert_eq(g.key_label, "E")
	assert_eq(g.hold_fraction, -1.0)
	assert_eq(InteractionVerbs.for_seen(SeenKind.Kind.LEVER), "verb.lever")
	assert_eq(UiText.text("verb.lever"), "Pull lever")
