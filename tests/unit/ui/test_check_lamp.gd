extends GutTest
## UI-01's Check Lamp: while held, with a lamp in hand, the oil line against lamp.check_marks (4)
## marks, notches out of lamp.max_notches (3) and the flame side-on; a shuttered lamp only lit or out;
## released or no lamp in hand, nothing. Holding it changes no server state (MNR-07's
## test_check_lamp_data: only the holder's record rides).

const W = preload("res://tests/unit/ui/inplay_world.gd")


func before_all() -> void:
	assert_true(Tuning.load_client())


func _inv(check: Dictionary, shut: bool = false) -> Dictionary:
	var d: Dictionary = {"lamp": [ItemKinds.Kind.GAUZE_LAMP, 0], "lamp_shut": shut}
	if not check.is_empty():
		d["check"] = check
	return d


func test_marks_and_notches_are_the_designs() -> void:
	assert_eq(roundi(Tuning.f(&"lamp.check_marks")), 4)
	assert_eq(roundi(Tuning.f(&"lamp.max_notches")), 3)


func test_shown_only_while_held_with_a_lamp() -> void:
	var c: CheckLampOverlay = CheckLampOverlay.new()
	add_child_autofree(c)
	c.update(true, _inv({"oil48": 24, "notches": 2}), 1)
	assert_true(c.visible)
	assert_eq(int(Variants.number(c.check["oil48"])), 24)
	assert_true(c.lit)
	c.update(false, _inv({"oil48": 24, "notches": 2}), 1)
	assert_false(c.visible, "released: gone")
	c.update(true, {"lamp": [0, 0]}, 0)
	assert_false(c.visible, "no lamp in hand: nothing")
	c.update(true, _inv({}, true), 0)
	assert_true(c.visible, "a shuttered lamp: lit or out only")
	assert_true(c.shut)
	assert_false(c.lit)


func test_the_layer_follows_the_hold_and_the_dark_is_no_bar() -> void:
	var l: InPlayLayer = InPlayLayer.new()
	add_child_autofree(l)
	var r: InputRouter = InputRouter.new()
	var v: ReceivedView = W.view(Vector2(4, 4))
	var inv: Dictionary = _inv({"oil48": 10, "notches": 0})
	l.update(W.frame(v, r, {"inventory": inv}))
	assert_false(l.check_lamp.visible)
	r.record.holds = InputRecord.HOLD_CHECK_LAMP
	l.update(W.frame(v, r, {"inventory": inv}))
	assert_true(l.check_lamp.visible, "needs no light: shown whatever the flame")
	assert_almost_eq(l.check_lamp.position.y, 0.0, 0.01)
	assert_almost_eq(Tuning.f(&"camera.check_lamp_panel_height"), 0.33, 1e-6, "the lower third; the mine above it")


func test_it_draws() -> void:
	var c: CheckLampOverlay = CheckLampOverlay.new()
	add_child_autofree(c)
	for inv: Dictionary in [_inv({"oil48": 48, "notches": 3}), _inv({"oil48": 0, "notches": 0}), _inv({}, true)]:
		c.update(true, inv, 1)
		c.queue_redraw()
		await wait_process_frames(1)
	assert_true(c.visible)
