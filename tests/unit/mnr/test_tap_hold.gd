extends GutTest
## MNR-15 (§4.8 rule 5): LB and View under movement.input_tap_max (0.2 s) are taps (the rock with
## the stick centred; the Pocket Book), longer is a hold (the callout wheel; Check Lamp, shown once
## the hold passes 0.2 s). A: interact from the press; a tap with a lamp in hand and nothing
## identified starts set down, cancelled by moving or a second tap.

const F = preload("res://tests/unit/mnr/input_frames.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_lb_tap_is_the_rock_and_hold_the_wheel() -> void:
	var r: InputRouter = F.router("pad")
	var lb: Dictionary = F.pad_button(r.store, JOY_BUTTON_LEFT_SHOULDER)
	var opened: Array[bool] = []
	var sent: Array = F.press(r, lb, 1.0, 0.19)
	assert_eq(F.kinds(sent), [ActionRecord.Kind.TAP_ROCK] as Array[int], "0.19 s: the rock")
	# 0.21 s: the wheel is open before the release, and no rock.
	var t: float = 3.0
	while t < 3.21 - 1e-9:
		r.sample(F.frame(t, lb))
		opened.append(r.context == InputContexts.Context.WHEEL)
		assert_eq(r.actions, [])
		t += F.FRAME_S
	assert_true(opened[-1], "0.21 s: the callout wheel")
	assert_false(opened[0], "not before 0.2 s")
	r.sample(F.frame(3.21, {}))
	assert_eq(r.actions, [], "released centred: nothing")


func test_lb_tap_with_the_stick_deflected_is_no_rock() -> void:
	var r: InputRouter = F.router("pad")
	var lb: Dictionary = F.pad_button(r.store, JOY_BUTTON_LEFT_SHOULDER)
	assert_eq(F.press(r, lb, 1.0, 0.1, {"wheel_vec": Vector2(0.8, 0)}), [])


func test_view_tap_is_the_book_and_hold_check_lamp() -> void:
	var r: InputRouter = F.router("pad")
	var view: Dictionary = F.pad_button(r.store, JOY_BUTTON_BACK)
	var t: float = 1.0
	while t < 1.19 - 1e-9:
		r.sample(F.frame(t, view))
		assert_eq(r.record.holds & InputRecord.HOLD_CHECK_LAMP, 0, "no Check Lamp inside a tap")
		t += F.FRAME_S
	r.sample(F.frame(1.19, {}))
	assert_eq(r.pocket_book_presses, 1, "0.19 s: the Pocket Book")
	var first_held: float = -1.0
	t = 2.0
	while t < 2.5:
		r.sample(F.frame(t, view))
		if first_held < 0.0 and (r.record.holds & InputRecord.HOLD_CHECK_LAMP) != 0:
			first_held = t - 2.0
		t += F.FRAME_S
	r.sample(F.frame(2.5, {}))
	assert_almost_eq(first_held, 0.2, F.FRAME_S, "Check Lamp once the hold passes 0.2 s")
	assert_eq(r.pocket_book_presses, 1, "a hold is no book")
	assert_eq(r.record.holds & InputRecord.HOLD_CHECK_LAMP, 0, "released")


func test_keyboard_has_its_own_keys() -> void:
	var r: InputRouter = F.router()
	assert_eq(F.kinds(F.press(r, {"tap_rock": true}, 1.0, 0.5)), [ActionRecord.Kind.TAP_ROCK] as Array[int], "T: the rock, however long")
	r.sample(F.frame(2.0, {"pocket_book": true}))
	assert_eq(r.pocket_book_presses, 1, "M")
	r.sample(F.frame(2.05, {"check_lamp": true}))
	assert_ne(r.record.holds & InputRecord.HOLD_CHECK_LAMP, 0, "Tab: at once")


func test_pad_a_interacts_at_once_and_a_tap_sets_down() -> void:
	var r: InputRouter = F.router("pad")
	var a: Dictionary = F.pad_button(r.store, JOY_BUTTON_A)
	r.lamp_in_hand = true
	r.sample(F.frame(1.0, a))
	assert_ne(r.record.holds & InputRecord.HOLD_INTERACT, 0, "interact from the press: no timed action runs long")
	r.sample(F.frame(1.1, {}))
	assert_ne(r.record.holds & InputRecord.HOLD_SET_DOWN, 0, "a tap with a lamp in hand: set down")
	assert_eq(r.record.holds & InputRecord.HOLD_INTERACT, 0)
	r.sample(F.frame(1.2, {}))
	assert_ne(r.record.holds & InputRecord.HOLD_SET_DOWN, 0, "kept until it ends")
	r.sample(F.frame(1.3, {}, {"move": Vector2(1, 0)}))
	assert_eq(r.record.holds & InputRecord.HOLD_SET_DOWN, 0, "moving cancels it")
	F.press(r, a, 2.0, 0.1)
	assert_ne(r.record.holds & InputRecord.HOLD_SET_DOWN, 0)
	F.press(r, a, 2.5, 0.1)
	assert_eq(r.record.holds & InputRecord.HOLD_SET_DOWN, 0, "a second tap cancels it")
	# A long hold is interact (feel) only.
	F.press(r, a, 3.0, 0.5)
	assert_eq(r.record.holds & InputRecord.HOLD_SET_DOWN, 0)
	# Something identified in reach takes A: a tap is interact only (the ring opens on a tap).
	r.target_in_reach = true
	F.press(r, a, 4.0, 0.1)
	assert_eq(r.record.holds & InputRecord.HOLD_SET_DOWN, 0)
	# No lamp in hand: no set down.
	r.target_in_reach = false
	r.lamp_in_hand = false
	F.press(r, a, 5.0, 0.1)
	assert_eq(r.record.holds & InputRecord.HOLD_SET_DOWN, 0)


## §4.8 rule 6: left mouse does nothing in the mine unless the revolver is drawn (and aimed).
func test_left_mouse_needs_the_drawn_revolver() -> void:
	var r: InputRouter = F.router()
	var before: Array = [r.record.holds, r.record.desired, r.record.move_dir]
	r.sample(F.frame(1.0, {"fire": true}))
	assert_eq(r.actions, [], "nothing drawn: no intent")
	assert_eq([r.record.holds, r.record.desired, r.record.move_dir], before, "and no held bit or state")
	r.sample(F.frame(1.1, {}))
	r.revolver_drawn = true
	r.sample(F.frame(1.2, {"fire": true}))
	assert_eq(r.actions, [], "drawn but not aimed: no shot")
	r.sample(F.frame(1.3, {"squint": true}))
	assert_ne(r.record.holds & InputRecord.HOLD_AIM, 0, "right mouse aims the drawn revolver")
	r.sample(F.frame(1.4, {"squint": true, "fire": true}))
	assert_eq(F.kinds(r.actions), [ActionRecord.Kind.TRIGGER] as Array[int], "drawn and aimed: the trigger")
	# The inventory says what is drawn.
	var k: InputRouter = F.router()
	k.know_inventory({"lamp": [ItemKinds.Kind.GAUZE_LAMP, 1], "free": [ItemKinds.Kind.REVOLVER, 1]})
	assert_true(k.revolver_drawn and k.lamp_in_hand)
	k.know_inventory({"lamp": [ItemKinds.Kind.NONE, 0], "free": [ItemKinds.Kind.NONE, 0]})
	assert_false(k.revolver_drawn or k.lamp_in_hand)
	# In a close-up left mouse is the pencil, never a shot.
	k.revolver_drawn = true
	k.open_close_up()
	k.sample(F.frame(2.0, {"pencil": true, "fire": true, "squint": true}))
	assert_eq(k.actions, [])
	assert_eq(k.close_up_events, ["pencil"] as Array[String])
