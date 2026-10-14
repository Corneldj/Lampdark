extends GutTest
## UI-01's arc (UI-03 reuses it) and the feel glyph: an arc on a circle round the own miner toward a
## bearing (16 steps clockwise from east), never a distance; the feel glyph beside the own miner with
## its caption and verb, for vision.feel_hold_s, never at the thing.

const W = preload("res://tests/unit/ui/inplay_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_client())


func test_the_arc_is_a_direction_only() -> void:
	var a: ArcWidget = ArcWidget.new()
	add_child_autofree(a)
	a.set_arc(true, Vector2(100, 100), 90.0, 70.0)
	assert_true(a.visible)
	assert_eq(a.position, Vector2(100, 100), "centred on the miner")
	assert_eq(a.bearing_deg, 90.0)
	var far: ArcWidget = ArcWidget.new()
	add_child_autofree(far)
	far.set_arc(true, Vector2(100, 100), 90.0, 70.0)
	assert_eq(far.radius_px, a.radius_px, "the same arc whatever the distance")
	a.set_arc(false, Vector2.ZERO, 0.0, 70.0)
	assert_false(a.visible)
	assert_eq(ScreenElementRegistry.type_of(a), &"arc")


func test_the_feel_glyph_beside_the_miner_with_an_arc_on_the_bearing() -> void:
	var g: FeelGlyph = FeelGlyph.new()
	add_child_autofree(g)
	add_child_autofree(g.arc)
	var feel: FeelClient = FeelClient.new()
	feel.last_feel = {"caption_key": "feel.item.spanner", "bearing_q": 4, "verb_key": "verb.pick_up"}
	feel.feels = 1
	g.update(feel, Vector2(960, 540), 64.0, 10.0)
	assert_true(g.visible)
	assert_eq(g.caption_key, "feel.item.spanner")
	assert_eq(g.verb_key, "verb.pick_up")
	assert_eq(g.position, Vector2(960, 540) + FeelGlyph.BESIDE, "beside the own miner")
	assert_true(g.arc.visible)
	assert_almost_eq(g.arc.bearing_deg, 90.0, 1e-6, "step 4: south on screen")
	assert_eq(g.arc.position, Vector2(960, 540))
	g.update(feel, Vector2(960, 540), 64.0, 10.0 + Tuning.f(&"vision.feel_hold_s") + 0.01)
	assert_false(g.visible, "held for vision.feel_hold_s")
	assert_false(g.arc.visible)


func test_nothing_felt_and_a_bump_have_no_arc() -> void:
	var g: FeelGlyph = FeelGlyph.new()
	add_child_autofree(g)
	add_child_autofree(g.arc)
	var feel: FeelClient = FeelClient.new()
	feel.last_feel = {"caption_key": "feel.nothing", "bearing_q": FeelMessages.NO_BEARING, "verb_key": ""}
	feel.feels = 1
	g.update(feel, Vector2.ZERO, 64.0, 1.0)
	assert_true(g.visible)
	assert_false(g.arc.visible, "'[nothing]': no direction")
	feel.last_bump = {"caption_key": "caption.bump.rock"}
	feel.bumps = 1
	g.update(feel, Vector2.ZERO, 64.0, 2.0)
	assert_eq(g.caption_key, "caption.bump.rock")
	assert_eq(g.verb_key, "")
	assert_false(g.arc.visible)
	await wait_process_frames(1)
