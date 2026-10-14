extends GutTest
## UI-01 on SND-06's breath-cloud: it shows the band the own voice frames carry (the band the server
## applies, SND-07) only while they are sent; nothing with push-to-talk released or on Mute; an Aside
## shows the whisper wisp. Only the own miner has one, and no client is ever sent another's band
## (SND-09's test_no_client_is_sent_a_band).


func before_all() -> void:
	assert_true(Tuning.load_client())


func test_band_only_while_sent() -> void:
	for band: int in [VoiceBands.Band.WHISPER, VoiceBands.Band.TALK, VoiceBands.Band.SHOUT, VoiceBands.Band.SCREAM]:
		assert_eq(InPlayLayer.breath_band(band, true, true, false), band, "sent: its own band")
		assert_eq(InPlayLayer.breath_band(band, false, true, false), VoiceBands.Band.SILENT, "push-to-talk released: none")
		assert_eq(InPlayLayer.breath_band(band, true, false, false), VoiceBands.Band.SILENT, "Mute: none")
		assert_eq(InPlayLayer.breath_band(band, true, true, true), VoiceBands.Band.WHISPER, "the Aside: the wisp")


func test_push_to_talk_gates_sending() -> void:
	var b: VoiceBands = VoiceBands.new()
	b.band = VoiceBands.Band.TALK
	b.push_to_talk = true
	b.ptt_held = false
	assert_eq(InPlayLayer.breath_band(b.band, b.sending(), true, false), VoiceBands.Band.SILENT)
	b.ptt_held = true
	assert_eq(InPlayLayer.breath_band(b.band, b.sending(), true, false), VoiceBands.Band.TALK)


func test_four_shapes_and_the_own_miner_only() -> void:
	var wv: WorldView = WorldView.new()
	add_child_autofree(wv)
	assert_eq(wv.find_children("*", "BreathCloud", true, false).size(), 1)
	assert_eq(ScreenElementRegistry.type_of(wv.breath), &"breath_cloud")
	var src: String = FileAccess.get_file_as_string("res://client/client_main.gd")
	assert_true(src.contains("InPlayLayer.breath_band(voice_bands.band, voice_bands.sending(),"), "the client gates it")
	assert_true(src.contains("mic_mode.voice_enabled()"), "Mute shows none")
