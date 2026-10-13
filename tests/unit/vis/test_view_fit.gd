extends GutTest
## VIS-01: the fixed 30 x 16.875-tile view fits any window, never widened, with pure-black bars:
## 64 px and no bars at 1920x1080; 42.67 px and 40 px bars at 1280x800; 64 px and 320 px pillars
## at 2560x1080; 128 px at 3840x2160; 30 tiles wide at 21:9 and 32:9.


func before_all() -> void:
	assert_true(Tuning.load_server())


func _check(window: Vector2i, tile_px: float, bars: Vector2) -> void:
	var f: Dictionary = ViewFit.fit(window)
	assert_almost_eq(float(Variants.number(f["tile_px"])), tile_px, 0.01, "%s: tile size" % window)
	var b: Vector2 = f["bars"]
	assert_almost_eq(b.x, bars.x, 0.01, "%s: side bars" % window)
	assert_almost_eq(b.y, bars.y, 0.01, "%s: top and bottom bars" % window)
	var tiles: Vector2 = f["visible_tiles"]
	assert_almost_eq(tiles.x, 30.0, 1e-4, "%s: 30 tiles wide" % window)
	assert_almost_eq(tiles.y, 16.875, 1e-4, "%s: 16.875 tiles high" % window)


func test_the_fit_table() -> void:
	_check(Vector2i(1920, 1080), 64.0, Vector2.ZERO)
	_check(Vector2i(1280, 800), 42.6667, Vector2(0, 40))
	_check(Vector2i(2560, 1080), 64.0, Vector2(320, 0))
	_check(Vector2i(3840, 2160), 128.0, Vector2.ZERO)


func test_never_widened() -> void:
	for window: Vector2i in [Vector2i(2520, 1080), Vector2i(3440, 1440), Vector2i(5120, 1440), Vector2i(3840, 1080),
			Vector2i(1024, 768), Vector2i(800, 1280)]:
		var f: Dictionary = ViewFit.fit(window)
		var tiles: Vector2 = f["visible_tiles"]
		assert_almost_eq(tiles.x, 30.0, 1e-4, "%s: still 30 tiles" % window)
		var b: Vector2 = f["bars"]
		assert_true(b.x >= -1e-6 and b.y >= -1e-6, "%s: bars, never cropping" % window)
		assert_true(b.x < 1e-6 or b.y < 1e-6, "%s: bars on one axis only" % window)


func test_project_letterboxes_in_pure_black() -> void:
	assert_eq(str(ProjectSettings.get_setting("display/window/stretch/mode")), "canvas_items")
	assert_eq(str(ProjectSettings.get_setting("display/window/stretch/aspect")), "keep", "never widened")
	assert_eq(int(Variants.number(ProjectSettings.get_setting("display/window/size/viewport_width"))), 1920)
	assert_eq(int(Variants.number(ProjectSettings.get_setting("display/window/size/viewport_height"))), 1080)
	var clear: Color = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color")
	assert_eq(clear, Color(0, 0, 0, 1), "the bars are the clear colour: pure black")
	assert_eq(ViewFit.BAR_COLOUR, Color(0, 0, 0, 1))
	assert_eq(ViewFit.base_px(), Vector2(1920, 1080), "30 x 16.875 tiles at 64 px is exactly 1080p")
