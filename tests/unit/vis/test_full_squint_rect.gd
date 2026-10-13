extends GutTest
## VIS-01: the shared geometry: full_squint_rect is the 30 x 16.875-tile view 8 tiles along the facing,
## the client's own view once its lead has settled at 8 tiles, and inside VIS-03's detail region (the
## same tuning the native frame reads), so a squint can never show a tile the server did not send.

const DT: float = 1.0 / 60.0


func before_all() -> void:
	assert_true(Tuning.load_server())


func test_matches_the_settled_squint_view() -> void:
	for deg: float in [0.0, 37.0, 90.0, 180.0, 251.0, 315.0]:
		var facing: int = Intents.facing_u16(deg)
		var at: Vector2 = Vector2(12.25, -4.5)
		var shared: Rect2 = ViewGeometry.full_squint_rect(at, facing)
		assert_almost_eq(shared.size.x, 30.0, 1e-9)
		assert_almost_eq(shared.size.y, 16.875, 1e-9)
		assert_almost_eq(shared.get_center().distance_to(at), 8.0, 1e-6, "8 tiles along the facing")
		var cam: LampCamera = LampCamera.new()
		for _i: int in 90:
			cam.follow(at, facing, true, DT)
		var mine: Rect2 = cam.view_rect(at)
		assert_almost_eq(mine.position.distance_to(shared.position), 0.0, 1e-3, "%.0f deg: the client's squint view" % deg)
		var detail: Rect2 = ViewGeometry.detail_rect(at, facing)
		assert_true(detail.encloses(mine), "%.0f deg: inside the server's detail region" % deg)
		cam.free()


func test_the_farthest_tile_is_about_25_away() -> void:
	var r: Rect2 = ViewGeometry.full_squint_rect(Vector2.ZERO, Intents.facing_u16(0.0))
	var far: float = maxf(r.position.length(), (r.position + r.size).length())
	assert_almost_eq(far, 25.0, 1.0, "§5.2: on-screen tiles lie within about 25 tiles")
