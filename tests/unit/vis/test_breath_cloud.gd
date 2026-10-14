extends GutTest
## SND-06: the breath-cloud. One per client, on the own miner's overlay, fed only by set_band (the
## own measurement): it sits ahead of the mouth, fades between shapes, and draws nothing for silence
## or in Dark (RSC-04's black mode).


func before_all() -> void:
	Tuning.load_client()


func test_it_sits_ahead_of_the_own_miners_mouth() -> void:
	var c: BreathCloud = BreathCloud.new()
	add_child_autofree(c)
	c.set_frame(true, Vector2(500, 300), Vector2(1, 0), 64.0, 0.0)
	assert_almost_eq(c.position.x, 500.0 + Tuning.f(&"voice.breath_cloud_offset_tiles") * 64.0, 0.01)
	assert_almost_eq(c.position.y, 300.0, 0.01)
	c.set_frame(true, Vector2(500, 300), Vector2(0, 1), 64.0, 0.0)
	assert_almost_eq(c.rotation, PI / 2.0, 0.001, "turned with the facing")


func test_it_fades_between_shapes() -> void:
	var c: BreathCloud = BreathCloud.new()
	add_child_autofree(c)
	c.set_band(3, 10.0)
	c.set_frame(true, Vector2.ZERO, Vector2(1, 0), 64.0, 10.0)
	assert_almost_eq(c.fade(), 0.0, 0.001)
	c.set_frame(true, Vector2.ZERO, Vector2(1, 0), 64.0, 10.0 + Tuning.f(&"voice.breath_cloud_fade_s") / 2.0)
	assert_almost_eq(c.fade(), 0.5, 0.01)
	c.set_frame(true, Vector2.ZERO, Vector2(1, 0), 64.0, 11.0)
	assert_eq(c.fade(), 1.0)


func test_the_world_view_has_exactly_one_and_only_for_the_own_miner() -> void:
	var wv: WorldView = WorldView.new()
	add_child_autofree(wv)
	assert_not_null(wv.breath)
	assert_eq(wv.find_children("*", "BreathCloud", true, false).size(), 1, "one cloud: the own miner's")
	# Nothing received can drive it: it has no input but set_band, and the client calls that only
	# with its own VoiceBands (client_main.gd).
	var src: String = FileAccess.get_file_as_string("res://client/client_main.gd")
	assert_eq(src.count("breath.set_band("), 1)
	assert_true(src.contains("world_view.breath.set_band(voice_bands.band"))
