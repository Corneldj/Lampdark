extends "res://tests/scenario/kit/scenario_test.gd"
## UI-01: through the M1 session the interaction glyph sits only on identity records within touch
## range; a fringe or margin token in reach never gets one (tokens carry no kind), and the same record
## demoted to a token loses its glyph.

const P = preload("res://tests/scenario/ui/in_play_session.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_glyph_only_on_identity_records() -> void:
	var x: P.Session = P.run(self, 42)
	var glyphs: int = 0
	var tokens_in_reach: int = 0
	for f: Dictionary in x.frames:
		var target: Dictionary = f["target"]
		for n: Variant in Variants.array(f["near"]):
			if int(Variants.number(Variants.dict(n)["level"])) != 2:
				tokens_in_reach += 1
		if target.is_empty():
			continue
		glyphs += 1
		var token: int = int(Variants.number(target["token"]))
		var on: Dictionary = {}
		for n: Variant in Variants.array(f["near"]):
			if int(Variants.number(Variants.dict(n)["token"])) == token:
				on = n
		assert_false(on.is_empty(), "the glyph's thing is in touch range")
		assert_eq(int(Variants.number(on.get("level", -1))), 2, "an identity record, never a token")
	gut.p("frames with a glyph %d, token sightings in reach %d" % [glyphs, tokens_in_reach])
	assert_gt(glyphs, 0, "the spanner and Bob drew glyphs")


func test_a_record_demoted_to_a_token_loses_its_glyph() -> void:
	var x: P.Session = P.run(self, 43)
	var found: bool = false
	for f: Dictionary in x.frames:
		var target: Dictionary = f["target"]
		if target.is_empty():
			continue
		var v: ReceivedView = f["view"]
		var copy: ReceivedView = v.duplicate_view()
		var token: int = int(Variants.number(target["token"]))
		var e: Dictionary = Variants.dict(copy.entities[token]).duplicate()
		copy.entities[token] = {"level": 1, "size_or_kind": SeenKind.Size.SMALL, "position": e["position"]}
		var again: Dictionary = InteractionGlyph.pick(copy, Tuning.f(&"vision.touch_range_tiles"))
		assert_ne(int(Variants.number(again.get("token", -1))), token, "the token gets no glyph")
		found = true
		break
	assert_true(found)
