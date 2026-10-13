extends GutTest
## SND-03 (GDD §14.2): a 40 np shot at 0 tiles, boosted further, peaks under noise.limiter_ceiling_dbfs
## at the output: measured on the real mix (the Dummy driver mixes; a capture after the limiter).


func before_all() -> void:
	assert_true(Tuning.load_server())
	AudioBuses.install()


func test_shot_peaks_under_the_ceiling() -> void:
	var master: int = AudioServer.get_bus_index("Master")
	var cap: AudioEffectCapture = AudioEffectCapture.new()
	AudioServer.add_bus_effect(master, cap)
	var at: int = AudioServer.get_bus_effect_count(master) - 1
	var p: EventPlayer = EventPlayer.new()
	add_child_autofree(p)
	await get_tree().process_frame
	cap.clear_buffer()
	var r: AudioRecord = AudioRecord.new()
	r.type = NoiseTypes.Type.SHOT
	r.level_np = 40.0
	r.remaining_np = 40.0
	r.gain_db = 12
	for i: int in 4:
		p.play(r, i)
	var peak: float = 0.0
	var seen: int = 0
	# The native mixer feeds the buses through generators: wait for half a second of mixed audio,
	# not a count of (headless, very fast) frames.
	var want: int = roundi(AudioServer.get_mix_rate() * 0.5)
	for _i: int in 2000:
		if seen >= want:
			break
		await get_tree().process_frame
		var n: int = cap.get_frames_available()
		seen += n
		for f: Vector2 in cap.get_buffer(n):
			peak = maxf(peak, maxf(absf(f.x), absf(f.y)))
	AudioServer.remove_bus_effect(master, at)
	var ceiling: float = db_to_linear(Tuning.f(&"noise.limiter_ceiling_dbfs"))
	assert_gt(seen, 1000, "the mix ran")
	assert_gt(peak, 0.5, "the shot is loud")
	assert_lte(peak, ceiling + 1e-3, "and peaks under %.1f dBFS (%.3f)" % [Tuning.f(&"noise.limiter_ceiling_dbfs"), peak])
