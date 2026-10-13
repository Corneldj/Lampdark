extends GutTest
## MNR-15: a wheel opens on its button; the mouse distance or stick deflection and the angle are
## reported for SND-11's ring bounds; releasing centred sends nothing. Lamp signals, chalk, the job
## page and the interact ring use the same pick.

const F = preload("res://tests/unit/mnr/input_frames.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_mouse_pick_reports_angle_and_distance() -> void:
	var r: InputRouter = F.router()
	var sent: Array = F.press(r, {"callout": true}, 1.0, 0.5, {"wheel_vec": Vector2(0.6, 0.0)})
	assert_eq(sent.size(), 1)
	var a: Array = sent[0]
	assert_eq(int(Variants.number(a[0])), ActionRecord.Kind.CALLOUT)
	assert_eq(int(Variants.number(a[2])), 0, "east")
	assert_almost_eq(Variants.number(Intents.decode_wheel_arg(int(Variants.number(a[1])))["distance"]), 0.6, 0.001)
	# Each of SND-11's rings is reachable: the distance reaches its bounds unchanged.
	for d: float in Tuning.current.list_f(&"voice.wheel_ring_bounds"):
		var r2: InputRouter = F.router()
		var s2: Array = F.press(r2, {"callout": true}, 1.0, 0.3, {"wheel_vec": Vector2(0.0, -(d + 0.01))})
		var arg: Dictionary = Intents.decode_wheel_arg(int(Variants.number(Variants.array(s2[0])[1])))
		assert_almost_eq(Variants.number(arg["distance"]), d + 0.01, 0.001)
		assert_eq(int(Variants.number(Variants.array(s2[0])[2])), Intents.facing_u16(270.0), "north")


func test_stick_pick_reports_deflection() -> void:
	var r: InputRouter = F.router("pad")
	var store: BindingsStore = r.store
	var lb: Dictionary = F.pad_button(store, JOY_BUTTON_LEFT_SHOULDER)
	var sent: Array = F.press(r, lb, 1.0, 0.6, {"wheel_vec": Vector2(-0.9, 0.0)})
	assert_eq(F.kinds(sent), [ActionRecord.Kind.CALLOUT] as Array[int])
	assert_eq(int(Variants.number(Variants.array(sent[0])[2])), Intents.facing_u16(180.0))
	assert_almost_eq(Variants.number(Intents.decode_wheel_arg(int(Variants.number(Variants.array(sent[0])[1])))["distance"]), 0.9, 0.001)


func test_release_centred_cancels() -> void:
	var centre: float = WheelInput.cancel_radius()
	for family: String in ["kbm", "pad"]:
		var r: InputRouter = F.router(family)
		var button: Dictionary = {"callout": true} if family == "kbm" else F.pad_button(r.store, JOY_BUTTON_LEFT_SHOULDER)
		var sent: Array = F.press(r, button, 1.0, 0.5, {"wheel_vec": Vector2(centre * 0.8, 0.0)})
		assert_eq(sent, [], "%s: nothing sent" % family)
		assert_eq(r.context, InputContexts.Context.MINE)


func test_signal_chalk_and_job_page() -> void:
	var k: InputRouter = F.router()
	assert_eq(F.kinds(F.press(k, {"signal_wheel": true}, 1.0, 0.3, {"wheel_vec": Vector2(0, 0.7)})), [ActionRecord.Kind.LAMP_SIGNAL] as Array[int])
	assert_eq(F.kinds(F.press(k, {"chalk_wheel": true}, 2.0, 0.3, {"wheel_vec": Vector2(0, 0.7)})), [ActionRecord.Kind.CHALK] as Array[int])
	var p: InputRouter = F.router("pad")
	var sent: Array = F.press(p, F.pad_button(p.store, JOY_BUTTON_Y), 1.0, 0.3, {"wheel_vec": Vector2(0.7, 0)})
	assert_eq(F.kinds(sent), [ActionRecord.Kind.LAMP_SIGNAL] as Array[int], "Y: one wheel")
	assert_true(Variants.flag(Intents.decode_wheel_arg(int(Variants.number(Variants.array(sent[0])[1])))["combined"]), "chalk on it too")
	var c: InputRouter = F.router()
	c.carrying = true
	c.sample(F.frame(1.0, {"callout": true}))
	assert_true(c.wheel.job_page, "carrying: the job page in place of the callout wheel")
	c.sample(F.frame(1.1, {}))
	c.carrying = false
	c.sample(F.frame(1.2, {"callout": true}))
	assert_false(c.wheel.job_page)


func test_ring_choice() -> void:
	var r: InputRouter = F.router()
	r.know_ring({"open": true, "options": ["hand_over", "douse", "share_oil", "lift"]})
	assert_true(r.picking())
	# Up is the first option, then clockwise.
	var expect: Dictionary = {0: Vector2(0, -0.8), 1: Vector2(0.8, 0), 2: Vector2(0, 0.8), 3: Vector2(-0.8, 0)}
	var t: float = 1.0
	for raw: Variant in expect.keys():
		var sent: Array = F.press(r, {"interact": true}, t, 0.2, {"wheel_vec": expect[raw]})
		assert_eq(sent.size(), 1)
		assert_eq(Variants.array(sent[0]).slice(0, 2), [ActionRecord.Kind.RING_CHOICE, int(Variants.number(raw))])
		t += 1.0
	assert_eq(F.press(r, {"interact": true}, t, 0.2, {"wheel_vec": Vector2.ZERO}), [], "centred: no choice")
	r.know_ring({"open": false, "options": []})
	assert_false(r.picking())


func test_slices() -> void:
	assert_eq(WheelInput.slice(270.0, 8), 0, "straight up")
	assert_eq(WheelInput.slice(270.0 + 22.4, 8), 0)
	assert_eq(WheelInput.slice(270.0 + 22.6, 8), 1)
	assert_eq(WheelInput.slice(0.0, 4), 1, "east")
	assert_eq(WheelInput.slice(200.0, 4), 3, "west of north-west: the west slice of four")
