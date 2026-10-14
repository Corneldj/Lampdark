extends "res://tests/scenario/kit/scenario_test.gd"
## UI-01: on every frame of a scripted M1 session (the grey box: base camp, a lamp checked, a walk to
## a chamber, a feel in its black and the walk back), Ann's in-play layers hold only registered screen
## elements, and the elements the session calls for were shown.

const P = preload("res://tests/scenario/ui/in_play_session.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_every_frame_holds_only_registered_elements() -> void:
	var x: P.Session = P.run(self, 41)
	gut.p("frames %d, shown %s" % [x.frames.size(), x.shown.keys()])
	assert_gt(x.frames.size(), 200, "a session's worth of frames")
	var bad: Array[String] = []
	for f: Dictionary in x.frames:
		for v: Variant in Variants.array(f["violations"]):
			bad.append(str(v))
	assert_eq(bad, [] as Array[String], "nothing unregistered, ever")
	for type: StringName in [&"interaction_glyph", &"check_lamp", &"feel_glyph"]:
		assert_true(x.shown.has(type), "%s was shown" % type)
	# The check fails as soon as anything else is drawn.
	var stray: Label = Label.new()
	x.layer.add_child(stray)
	x.s.step(1)
	assert_eq(Variants.array(x.frames.back()["violations"]).size(), 1, "an unregistered node fails the frame")
