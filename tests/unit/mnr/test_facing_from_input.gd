extends GutTest
## MNR-15: facing turns at once toward the cursor, measured in screen space from the own miner's
## position with the camera's lead taken out, or along the right stick past its dead zone; a centred
## stick keeps it; it is held while a wheel is open. Movement is a direction only: half and full
## deflection send the same intent.

const F = preload("res://tests/unit/mnr/input_frames.gd")


func before_all() -> void:
	assert_true(Tuning.load_server())


func _deg(r: InputRouter) -> float:
	return r.record.facing / 65536.0 * 360.0


func test_mouse_facing_in_screen_space() -> void:
	var r: InputRouter = F.router()
	var own: Vector2 = Vector2(640, 360)
	r.sample(F.frame(0.0, {}, {"cursor": own + Vector2(100, 0), "own_screen": own}))
	assert_almost_eq(_deg(r), 0.0, 0.01, "east")
	r.sample(F.frame(0.1, {}, {"cursor": own + Vector2(0, -50), "own_screen": own}))
	assert_almost_eq(_deg(r), 270.0, 0.01, "straight up the screen, at once")
	r.sample(F.frame(0.2, {}, {"cursor": own + Vector2(-30, 30), "own_screen": own}))
	assert_almost_eq(_deg(r), 135.0, 0.01, "south-west, no turning rate")


func test_camera_lead_never_feeds_back() -> void:
	# The camera leads toward the facing: the whole view shifts, the cursor with it on the world, but
	# both the cursor and the own miner's unled position stay put on the screen, so facing holds.
	var r: InputRouter = F.router()
	var own: Vector2 = Vector2(640, 360)
	var cursor: Vector2 = own + Vector2(200, 80)
	r.sample(F.frame(0.0, {}, {"cursor": cursor, "own_screen": own}))
	var first: int = r.record.facing
	for i: int in 30:
		r.sample(F.frame(0.05 * (i + 1), {}, {"cursor": cursor, "own_screen": own, "camera_lead": Vector2(i * 4, i * 2)}))
		assert_eq(r.record.facing, first, "frame %d" % i)


func test_stick_facing_and_centred_stick_keeps_it() -> void:
	var r: InputRouter = F.router("pad")
	var dead: float = Tuning.f(&"movement.facing_dead_zone")
	r.sample(F.frame(0.0, {}, {"face_stick": Vector2(0.0, 1.0)}))
	assert_almost_eq(_deg(r), 90.0, 0.01, "stick down: south")
	r.sample(F.frame(0.05, {}, {"face_stick": Vector2(-0.4, 0.0)}))
	assert_almost_eq(_deg(r), 180.0, 0.01, "past the dead zone: west")
	r.sample(F.frame(0.1, {}, {"face_stick": Vector2(0.0, dead * 0.9)}))
	assert_almost_eq(_deg(r), 180.0, 0.01, "inside the dead zone: kept")
	r.sample(F.frame(0.15, {}, {}))
	assert_almost_eq(_deg(r), 180.0, 0.01, "centred: kept")


func test_facing_held_while_a_wheel_is_open() -> void:
	for family: String in ["kbm", "pad"]:
		var r: InputRouter = F.router(family)
		var own: Vector2 = Vector2(640, 360)
		r.sample(F.frame(0.0, {}, {"cursor": own + Vector2(100, 0), "own_screen": own, "face_stick": Vector2(1, 0)}))
		var held: int = r.record.facing
		var button: Dictionary = {"callout": true} if family == "kbm" else {"signal_wheel": true, "chalk_wheel": true}
		r.sample(F.frame(0.05, button, {"cursor": own + Vector2(100, 0), "own_screen": own, "face_stick": Vector2(1, 0)}))
		assert_eq(r.context, InputContexts.Context.WHEEL, family)
		for i: int in 20:
			var swing: Vector2 = Vector2.from_angle(i * 0.3)
			r.sample(F.frame(0.1 + 0.05 * i, button, {"cursor": own + swing * 150.0, "own_screen": own,
				"face_stick": swing, "wheel_vec": swing}))
			assert_eq(r.record.facing, held, "%s frame %d" % [family, i])
		r.sample(F.frame(2.0, {}, {"cursor": own + Vector2(0, 100), "own_screen": own, "face_stick": Vector2(0, 1)}))
		assert_eq(r.context, InputContexts.Context.MINE)
		assert_almost_eq(_deg(r), 90.0, 0.01, "%s: turns again once it closes" % family)


func test_movement_is_direction_only() -> void:
	var r: InputRouter = F.router("pad")
	var dead: float = Tuning.f(&"movement.stick_dead_zone")
	var dirs: Array[int] = []
	for deflection: float in [dead, 0.5, 0.75, 1.0]:
		r.sample(F.frame(0.0, {}, {"move": Vector2(0.6, 0.8) * deflection}))
		dirs.append(r.record.move_dir)
	assert_eq(dirs, [dirs[0], dirs[0], dirs[0], dirs[0]] as Array[int], "half and full deflection: one intent")
	assert_eq(dirs[0], Intents.direction_byte(rad_to_deg(Vector2(0.6, 0.8).angle())))
	r.sample(F.frame(0.0, {}, {"move": Vector2(0.6, 0.8) * dead * 0.9}))
	assert_eq(r.record.move_dir, InputRecord.NO_DIRECTION, "inside the dead zone: still")
	var k: InputRouter = F.router()
	k.sample(F.frame(0.0, {"move_up": true, "move_right": true}))
	assert_eq(k.record.move_dir, Intents.direction_byte(315.0), "W+D: north-east")
	# The record has no magnitude field at all: speed comes from the gait alone.
	var props: Array[String] = []
	for p: Dictionary in InputRecord.new().get_property_list():
		props.append(str(p["name"]))
	assert_false(props.has("speed") or props.has("magnitude") or props.has("deflection"))
