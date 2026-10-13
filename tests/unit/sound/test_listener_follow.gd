extends GutTest
## SND-04 (§6.10): the ears sit on the own miner and turn with its facing every frame, never with the
## camera: squinting or aiming moves the view's lead, not the listener.

const NORTH: int = 49152
const EAST: int = 0
const SOUTH: int = 16384


func before_all() -> void:
	assert_true(Tuning.load_server())
	AudioBuses.install()


func _rig() -> Array:
	var events: EventPlayer = EventPlayer.new()
	add_child_autofree(events)
	var ears: MinerListener = MinerListener.new(events.mixer, events)
	var tone: PackedFloat32Array = PackedFloat32Array()
	tone.resize(2048)
	tone.fill(0.25)
	var id: int = events.mixer.add(tone, 22050.0, Vector2(10.5, 2.5), 0.0, "Game", true)
	return [events, ears, id]


func test_follows_position_and_facing_every_frame() -> void:
	var rig: Array = _rig()
	var events: EventPlayer = rig[0]
	var ears: MinerListener = rig[1]
	var id: int = rig[2]
	ears.follow(Vector2(10.5, 8.5), NORTH)
	assert_almost_eq(events.mixer.native.azimuth_of(id), 0.0, 1e-6, "north of a miner facing north: ahead")
	assert_eq(events.listener, Vector2(10.5, 8.5), "the event player knows where the ears are")
	ears.follow(Vector2(10.5, 8.5), EAST)
	assert_almost_eq(events.mixer.native.azimuth_of(id), -90.0, 1e-6, "turn east: it is on the left")
	ears.follow(Vector2(10.5, 8.5), SOUTH)
	assert_almost_eq(absf(events.mixer.native.azimuth_of(id)), 180.0, 1e-6, "turn south: behind")
	assert_almost_eq(events.mixer.native.rear_cutoff_of(id), float(Tuning.i(&"noise.rear_lowpass_min_hz")), 1e-6, "and dull")
	ears.follow(Vector2(4.5, 2.5), NORTH)
	assert_almost_eq(events.mixer.native.azimuth_of(id), 90.0, 1e-6, "walk west of it: now on the right")


func test_squint_and_aim_move_the_camera_not_the_ears() -> void:
	var rig: Array = _rig()
	var events: EventPlayer = rig[0]
	var ears: MinerListener = rig[1]
	var id: int = rig[2]
	var camera: LampCamera = LampCamera.new()
	add_child_autofree(camera)
	var own: Vector2 = Vector2(10.5, 8.5)
	var heard: Array[float] = []
	var views: Array[Vector2] = []
	for squint: bool in [false, true]:
		for _f: int in 60:
			camera.follow(own, EAST, squint, 1.0 / 60.0)
			ears.follow(own, EAST)
		views.append(camera.view_rect(own).get_center())
		heard.append(events.mixer.native.azimuth_of(id))
	assert_gt(views[0].distance_to(views[1]), 1.0, "the squint's lead moved the view")
	assert_eq(heard[0], heard[1], "the ears did not move")
	assert_eq(ears.position, own)


func test_the_listener_never_reads_the_camera() -> void:
	var code: String = FileAccess.get_file_as_string("res://client/audio/miner_listener.gd")
	for line: String in code.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		assert_false(line.containsn("camera"), "no camera in: %s" % line)
