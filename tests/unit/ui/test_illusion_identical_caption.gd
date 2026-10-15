extends GutTest
## UI-03 (Gameplay §9.2): an illusion is captioned exactly as the sound it copies. The client has no
## illusion flag: a logged illusion and the real record it copies arrive as the same bytes, decode to
## the same record, play the same and caption the same: text, band, voice and arc.


func before_all() -> void:
	assert_true(Tuning.load_client())


func _from_bytes(event: Dictionary) -> AudioRecord:
	return AudioRecord.from_event(event)


func test_same_record_same_caption() -> void:
	var real: AudioRecord = AudioRecord.new()
	real.type = NoiseTypes.Type.TRAPPED_CRY
	real.start_tick = 400
	real.apparent = Vector2(23.5, 7.25)
	real.remaining_np = 4.0
	real.level_np = 9.0
	real.duration_s = 1.2
	real.voice = 3
	var illusion: AudioRecord = _from_bytes(real.to_event())
	var outputs: Array = []
	for r: AudioRecord in [real, illusion]:
		var player: EventPlayer = EventPlayer.new()
		add_child_autofree(player)
		var layer: CaptionLayer = CaptionLayer.new()
		add_child_autofree(layer)
		layer.wire(player, null, null, null, null, func() -> Vector2: return Vector2.ZERO)
		player.listener = Vector2(20, 10)
		player.play(r, 5)
		outputs.append(layer.system.history.duplicate(true))
	var a: Array = outputs[0]
	var b: Array = outputs[1]
	assert_eq(a, b, "the illusion's caption is the real sound's")
	var line: Dictionary = a[0]
	var bearing: Variant = line["bearing"]
	assert_string_contains(str(line["text"]), "the fourth voice", "with its character voice")
	assert_true(bearing != null, "and its arc")
