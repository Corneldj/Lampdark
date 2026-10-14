extends "res://tests/unit/vis/render/render_test.gd"
## SND-06: the breath-cloud draws at the own miner's mouth for a voiced band, over the dark, and
## nothing for silence. Its shapes grow from whisper to scream.


## Pixels in a small box ahead of the mouth that are not black.
func _lit_near_mouth(img: Image, facing_deg: float) -> int:
	var dir: Vector2 = Vector2.from_angle(deg_to_rad(facing_deg))
	var centre: Vector2 = K.MINER + dir * (Tuning.f(&"voice.breath_cloud_offset_tiles") + 0.45)  # clear of the miner's own sprite
	var c: Vector2i = K.px(centre)
	var r: int = roundi(Tuning.f(&"camera.tile_px_at_1080p") * 0.35)
	var n: int = 0
	for y: int in range(c.y - r, c.y + r):
		for x: int in range(c.x - r, c.x + r):
			if not K.is_black(img.get_pixel(x, y)):
				n += 1
	return n


func test_a_voiced_band_draws_at_the_mouth_and_silence_draws_nothing() -> void:
	if skip_without_renderer():
		return
	var view: ReceivedView = K.view_with({})
	var drawn: DrawnSet = K.drawn_from(view)
	var counts: Array[int] = []
	for band: int in [0, 1, 3, 4]:
		wv.breath.set_band(band, -10.0)  # long since faded in at the frame's time 0
		var img: Image = await render(view, drawn, Intents.facing_u16(0.0), 0.0)
		counts.append(_lit_near_mouth(img, 0.0))
	gut.p("lit pixels near the mouth: silent %d, whisper %d, shout %d, scream %d" % counts)
	assert_eq(counts[0], 0, "silent: no cloud")
	assert_gt(counts[1], 0, "a whisper: a wisp")
	assert_gt(counts[2], counts[1], "a shout: a full cloud, bigger than a wisp")
	assert_gt(counts[3], 0, "a scream: a torn cloud")
