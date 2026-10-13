extends GutTest
## SND-03: the mine's quiet bed always plays and never stops by itself; server cues start and stop
## layers (base camp's hum and draught for `base_camp`), each raising the silence-caption hook at its
## start and end; the cue survives the wire.


func before_all() -> void:
	assert_true(Tuning.load_server())
	AudioBuses.install()


func test_bed_never_stops_by_itself() -> void:
	var beds: AmbientBeds = AmbientBeds.new()
	add_child_autofree(beds)
	for layer: StringName in AmbientBeds.MINE_LAYERS:
		assert_true(beds.playing(layer), "%s plays" % layer)
	Engine.time_scale = 20.0
	await get_tree().create_timer(30.0).timeout
	Engine.time_scale = 1.0
	for layer: StringName in AmbientBeds.MINE_LAYERS:
		assert_true(beds.playing(layer), "%s still plays after 30 s" % layer)
		var p: AudioStreamPlayer = beds.players[layer]
		assert_true(p.playing, "and is really playing")
		assert_eq(p.bus, "Ambience")


func test_cues_start_and_stop_layers_with_captions() -> void:
	var beds: AmbientBeds = AmbientBeds.new()
	add_child_autofree(beds)
	var caps: Array = []
	beds.silence_caption.connect(func(layer: StringName, start: bool) -> void: caps.append([layer, start]))
	beds.apply(AmbientMessages.decode(AmbientMessages.encode(AmbientMessages.BASE_CAMP, true, 1.5)))
	assert_true(beds.playing(&"hum") and beds.playing(&"draught"), "base camp's bed")
	beds.apply({"layer": &"drips", "start": false, "fade_s": 2.0})
	assert_false(beds.playing(&"drips"), "the drip stops: an event")
	beds.apply({"layer": AmbientMessages.BASE_CAMP, "start": false, "fade_s": 1.0})
	assert_false(beds.playing(&"hum"))
	assert_eq(caps, [[AmbientMessages.BASE_CAMP, true], [&"drips", false], [AmbientMessages.BASE_CAMP, false]], "a caption hook at each start and end")


func test_message_round_trip() -> void:
	var cue: Dictionary = AmbientMessages.decode(AmbientMessages.encode(&"seam", false, 3.25))
	assert_eq(cue, {"layer": &"seam", "start": false, "fade_s": 3.25})
	assert_eq(AmbientMessages.decode(PackedByteArray([9, 1])), {}, "malformed: nothing")
