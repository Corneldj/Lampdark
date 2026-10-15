extends GutTest
## UI-03: recorded speech is subtitled by default, and with captions off; subtitles leave when their
## line and its linger end. The caption layer holds only registered screen elements (UI-01).


func before_all() -> void:
	assert_true(Tuning.load_client())


func test_subtitles_show_with_captions_off() -> void:
	var sys: CaptionSystem = CaptionSystem.new()
	assert_true(sys.subtitles_on, "on by default")
	sys.captions_on = false
	var doc: Dictionary = Variants.dict(JSON.parse_string(FileAccess.get_file_as_string("res://data/text/callouts/en.json")))
	var strings: Dictionary = Variants.dict(doc.get("strings", {}))
	var key: String = str(strings.keys()[0])
	sys.subtitle(key, 2.0, 0.0)
	assert_eq(sys.visible_subtitles(), [UiText.text(key)] as Array[String])
	assert_eq(sys.visible_lines(), [] as Array[Dictionary], "captions off: no caption lines")
	sys.tick(2.0 + Tuning.f(&"noise.caption_linger_s") + 0.01)
	assert_eq(sys.visible_subtitles(), [] as Array[String])


func test_the_caption_layer_holds_only_registered_elements() -> void:
	var layer: CaptionLayer = CaptionLayer.new()
	add_child_autofree(layer)
	layer.system.on_played(_record(), Vector2(3, 0), 0.0)
	layer.captions.refresh(0.0)
	assert_eq(ScreenElementRegistry.violations([layer] as Array[Node]), [] as Array[String])
	assert_eq(layer.layer, CloseupManager.CAPTIONS_LAYER, "above the close-ups")


func _record() -> AudioRecord:
	var r: AudioRecord = AudioRecord.new()
	r.type = NoiseTypes.Type.HAMMER
	r.duration_s = 0.5
	return r
