extends GutTest
## UI-03: captions come only from what plays. Each record EventPlayer plays yields one caption line
## (or freshens an identical one); a drawn-only visual event yields none; and the caption code reads
## no world, frame or server state (statically: it names none of them).


func before_all() -> void:
	assert_true(Tuning.load_client())


func _record(type: int, at: Vector2, flags: int = 0) -> AudioRecord:
	var r: AudioRecord = AudioRecord.new()
	r.type = type
	r.apparent = at
	r.remaining_np = 3.0
	r.level_np = 6.0
	r.duration_s = 0.5
	r.flags = flags
	return r


func test_one_line_per_played_event_and_none_otherwise() -> void:
	var player: EventPlayer = EventPlayer.new()
	add_child_autofree(player)
	var layer: CaptionLayer = CaptionLayer.new()
	add_child_autofree(layer)
	layer.wire(player, null, null, null, null, func() -> Vector2: return Vector2.ZERO)
	var sys: CaptionSystem = layer.system
	player.listener = Vector2(10, 10)
	player.play(_record(NoiseTypes.Type.GATE, Vector2(14, 10)), 1)
	assert_eq(sys.history.size(), 1, "one played record, one caption")
	assert_eq(sys.lines.size(), 1)
	player.play(_record(NoiseTypes.Type.GATE, Vector2(14, 10)), 2)
	assert_eq(sys.lines.size(), 1, "an identical repeat merges")
	player.play(_record(NoiseTypes.Type.COUGH, Vector2(10, 4)), 3)
	assert_eq(sys.lines.size(), 2)
	player.play(_record(VisualEvents.Type.PUFF, Vector2(12, 10)), 4)
	assert_eq(sys.history.size(), 3, "a drawn-only visual event is never played or captioned")
	var shown: Array[Dictionary] = sys.visible_lines()
	assert_eq(str(shown[0]["text"]), "[a gate clanging]")
	assert_eq(str(shown[1]["text"]), "[cough]")


func test_the_caption_code_reads_nothing_but_what_played() -> void:
	for path: String in ["res://client/ui/captions/caption_system.gd", "res://client/ui/captions/caption_layer.gd",
			"res://client/ui/captions/caption_view.gd", "res://client/ui/captions/caption_table.gd"]:
		var text: String = FileAccess.get_file_as_string(path)
		for word: String in ["ClientConnection", "ReceivedView", "FrameDecoder", "Protocol", "connection.", "RunState", "illusion_id",
				"is_illusion", "lie_log"]:
			assert_false(text.contains(word), "%s never reads %s" % [path, word])
