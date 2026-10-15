extends GutTest
## UI-01's wheel: slices from straight up clockwise as MNR-15 counts them, the callout wheel's three
## band rings at voice.wheel_ring_bounds, the centre that cancels, the job page in place of the
## callouts while carrying, the pad's one wheel of signals and chalk, drawn at ui.wheel_radius of the
## short side where the cursor stood.

const W = preload("res://tests/unit/ui/inplay_world.gd")
const F = preload("res://tests/unit/mnr/input_frames.gd")


func before_all() -> void:
	assert_true(Tuning.load_client())


func _wheel() -> WheelWidget:
	var w: WheelWidget = WheelWidget.new()
	add_child_autofree(w)
	return w


func test_slices() -> void:
	assert_eq(WheelWidget.slices_for("callout").size(), 12)
	assert_eq(WheelWidget.slices_for("callout", true), ["callout.now", "callout.right", "callout.stop", "callout.left"] as Array[String])
	assert_eq(WheelWidget.slices_for("signal").size(), 5, "SND-12's five lamp signals")
	var chalk: Array[String] = WheelWidget.slices_for("chalk")
	assert_eq(chalk.slice(0, 3), ["wheel.chalk.arrow", "wheel.chalk.cross", "wheel.chalk.bang"] as Array[String])
	assert_eq(chalk.size(), 13, "the arrow, X, '!' and the digits 0-9")
	assert_eq(WheelWidget.slices_for("combined"), WheelWidget.slices_for("signal") + WheelWidget.slices_for("chalk"))


func test_rings_pick_whisper_talk_shout_and_the_centre_cancels() -> void:
	var w: WheelWidget = _wheel()
	var bounds: PackedFloat64Array = Tuning.current.list_f(&"voice.wheel_ring_bounds")
	assert_eq(bounds.size(), 3, "the cancel edge, then the talk and shout rings' inner edges")
	w.show_wheel(true, Vector2(960, 540), WheelWidget.slices_for("callout"), true, Vector2(0.0, -(bounds[0] + 0.01)), 1080.0)
	assert_eq(w.picked(), Vector2i(0, 0), "straight up, inner ring: whisper")
	w.vec = Vector2(0.0, -(bounds[1] + 0.01))
	assert_eq(w.picked(), Vector2i(0, 1), "middle: talk")
	w.vec = Vector2(0.0, -0.99)
	assert_eq(w.picked(), Vector2i(0, 2), "outer: shout")
	w.vec = Vector2(bounds[0] * 0.5, 0.0)
	assert_eq(w.picked(), Vector2i(-1, -1), "centred: cancel")
	w.vec = Vector2(0.9, 0.0)
	assert_eq(w.picked().x, 3, "east is slice 3 of 12, clockwise")
	assert_almost_eq(w.radius_px, Tuning.f(&"ui.wheel_radius") * 1080.0, 0.01)


func test_the_layer_opens_the_routers_wheel_and_job_page() -> void:
	var l: InPlayLayer = InPlayLayer.new()
	add_child_autofree(l)
	var r: InputRouter = F.router()
	var v: ReceivedView = W.view(Vector2(3, 3))
	r.sample(F.frame(1.0, {"callout": true}))
	assert_eq(r.context, InputContexts.Context.WHEEL)
	l.update(W.frame(v, r, {"wheel_anchor": Vector2(700, 400)}))
	assert_true(l.wheel.visible)
	assert_eq(l.wheel.slices.size(), 12)
	assert_true(l.wheel.rings, "the callout wheel has band rings")
	assert_eq(l.wheel.position, Vector2(700, 400), "where the cursor stood")
	r.sample(F.frame(1.1, {}))
	l.update(W.frame(v, r))
	assert_false(l.wheel.visible, "closed on release")
	r.carrying = true
	r.sample(F.frame(2.0, {"callout": true}))
	l.update(W.frame(v, r))
	assert_eq(l.wheel.slices, WheelWidget.slices_for("callout", true), "carrying: the job page")
	assert_false(l.wheel.rings)
	r.sample(F.frame(2.1, {}))
	r.carrying = false
	var p: InputRouter = F.router("pad")
	p.sample(F.frame(3.0, F.pad_button(p.store, JOY_BUTTON_Y)))
	l.update(W.frame(v, p))
	assert_eq(l.wheel.slices, WheelWidget.slices_for("combined"), "the pad's Y: signals and chalk on one wheel")
	for kind: String in ["signal_wheel", "chalk_wheel"]:
		var k: InputRouter = F.router()
		k.sample(F.frame(4.0, {kind: true}))
		l.update(W.frame(v, k))
		assert_eq(l.wheel.slices, WheelWidget.slices_for("signal" if kind == "signal_wheel" else "chalk"))
		assert_false(l.wheel.rings)


func test_it_draws_with_and_without_rings() -> void:
	var w: WheelWidget = _wheel()
	w.show_wheel(true, Vector2(960, 540), WheelWidget.slices_for("callout"), true, Vector2(0.5, 0.5), 1080.0)
	await wait_process_frames(1)
	w.show_wheel(true, Vector2(960, 540), WheelWidget.slices_for("combined"), false, Vector2.ZERO, 800.0)
	await wait_process_frames(1)
	assert_true(w.visible)
	w.show_wheel(true, Vector2.ZERO, [] as Array[String], false, Vector2.ZERO, 800.0)
	assert_false(w.visible, "no slices: nothing")
