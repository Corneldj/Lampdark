extends GutTest
## VIS-01: no input, setting or state zooms, rotates or frees the camera: rotation stays 0, the zoom 1,
## north up, through every facing, squint, aim, state and shake.

const DT: float = 1.0 / 60.0


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_never_rotates_or_zooms() -> void:
	var cam: LampCamera = LampCamera.new()
	assert_true(cam.ignore_rotation)
	for state: LampCamera.State in [LampCamera.State.MINE, LampCamera.State.COMING_ROUND, LampCamera.State.CLOSE_UP]:
		cam.state = state
		for facing: int in [0, 8000, 16384, 30000, 49152, 65535]:
			for squint: bool in [false, true]:
				cam.add_shake(1.0, 0.2)
				for _i: int in 5:
					cam.follow(Vector2(7, 3), facing, squint, DT)
				assert_eq(cam.rotation, 0.0, "rotation 0")
				assert_eq(cam.zoom, Vector2.ONE, "never zoomed")
	# Even if something sets them, the next frame restores them.
	cam.state = LampCamera.State.MINE
	cam.rotation = 1.0
	cam.zoom = Vector2(0.5, 0.5)
	cam.follow(Vector2(7, 3), 0, false, DT)
	assert_eq(cam.rotation, 0.0)
	assert_eq(cam.zoom, Vector2.ONE)
	cam.free()
