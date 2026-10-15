extends GutTest
## SND-11: the wheel's slices are the drawn ones, in order; a pick's distance or stick deflection maps
## to whisper, talk or shout by voice.wheel_ring_bounds, the centre cancels, and nothing screams.


func before_all() -> void:
	assert_true(Tuning.load_client())


func test_the_lines_are_the_slices_drawn() -> void:
	for pair: Array in [[CalloutLines.WHEEL, "callout"], [CalloutLines.JOB_PAGE, "job_page"]]:
		var lines: Array[String] = pair[0]
		var drawn: Array = WheelWidget.SLICES[pair[1]]
		assert_eq(lines.size(), drawn.size())
		for i: int in lines.size():
			assert_eq("callout." + lines[i], str(drawn[i]), "slice %d" % i)
			var centre: float = fposmod(i * 360.0 / lines.size() - 90.0, 360.0)
			assert_eq(CalloutLines.slice(centre, lines.size()), i)
			assert_eq(CalloutLines.slice(centre, lines.size()), WheelInput.slice(centre, lines.size()), "the client counts alike")
			assert_false(VoiceManifest.frames_of("voice_1", lines[i], "talk") <= 0, "%s is recorded" % lines[i])
	assert_eq(CalloutLines.WHEEL.size(), 12)
	assert_eq(CalloutLines.JOB_PAGE.size(), 4)


func test_rings_by_distance_or_deflection() -> void:
	var bounds: Array[float] = Tuning.current.list_f(&"voice.wheel_ring_bounds")
	assert_eq(CalloutLines.band_of({"distance": 0.0}), 0, "the centre cancels")
	assert_eq(CalloutLines.band_of({"distance": bounds[0] - 0.01}), 0)
	assert_eq(CalloutLines.band_of({"distance": bounds[0]}), CalloutLines.WHISPER)
	assert_eq(CalloutLines.band_of({"distance": bounds[1] - 0.01}), CalloutLines.WHISPER)
	assert_eq(CalloutLines.band_of({"distance": bounds[1]}), CalloutLines.TALK)
	assert_eq(CalloutLines.band_of({"distance": bounds[2]}), CalloutLines.SHOUT)
	assert_eq(CalloutLines.band_of({"distance": 1.0}), CalloutLines.SHOUT, "the edge shouts; nothing screams")
	for band: int in [1, 2, 3]:
		var d: float = CalloutLines.ring_distance(band)
		var arg: int = Intents.wheel_arg_distance(d)
		assert_eq(CalloutLines.band_of(Intents.decode_wheel_arg(arg)), band, "band %d survives the wire" % band)


func test_a_centred_release_sends_nothing() -> void:
	var router: InputRouter = InputRouter.new()
	router.sample({"now_s": 0.0, "down": {}})
	router.sample({"now_s": 0.1, "down": {"callout": true}, "wheel_vec": Vector2.ZERO})
	router.sample({"now_s": 0.6, "down": {"callout": true}, "wheel_vec": Vector2(0.05, 0.0)})
	router.sample({"now_s": 0.7, "down": {}, "wheel_vec": Vector2(0.05, 0.0)})
	assert_false(router.actions.any(func(a: Array) -> bool: return int(Variants.number(a[0])) == ActionRecord.Kind.CALLOUT), "no callout")
