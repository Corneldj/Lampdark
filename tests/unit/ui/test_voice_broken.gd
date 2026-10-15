extends GutTest
## UI-03: an utterance reads '[voice]' while its frames arrive and '[voice, broken]' once one is
## concealed, with its loudest band as a word and an arc on its direction; a phone line reads
## '[voice, on the line]' and a dry channel '[voice]', both without an arc. Speech is never
## transcribed: the line's text comes only from its key.


func before_all() -> void:
	assert_true(Tuning.load_client())


func _header(at: Vector2, telephone: bool = false, dry: bool = false) -> Dictionary:
	return {"position": at, "telephone": telephone, "dry": dry, "gain_db": 0.0, "muffled": false}


func test_clean_and_broken() -> void:
	var sys: CaptionSystem = CaptionSystem.new()
	for i: int in 10:
		sys.on_voice(7, "frame", 2, _header(Vector2(15, 10)), Vector2(10, 10), i * 0.02)
	assert_eq(str(sys.visible_lines()[0]["text"]), "[voice] (spoken)")
	assert_almost_eq(float(Variants.number(sys.visible_lines()[0]["bearing"])), 0.0, 0.01, "east of the listener")
	sys.on_voice(7, "frame", 3, _header(Vector2(15, 10)), Vector2(10, 10), 0.3)
	assert_eq(str(sys.visible_lines()[0]["text"]), "[voice] (shouted)", "the loudest band")
	sys.on_voice(7, "conceal", 3, _header(Vector2(15, 10)), Vector2(10, 10), 0.32)
	sys.on_voice(7, "frame", 1, _header(Vector2(15, 10)), Vector2(10, 10), 0.34)
	assert_eq(str(sys.visible_lines()[0]["text"]), "[voice, broken] (shouted)", "a lost frame breaks it")
	sys.on_voice(7, "end", 0, _header(Vector2(15, 10)), Vector2(10, 10), 0.36)
	sys.tick(0.36 + Tuning.f(&"noise.caption_linger_s") - 0.01)
	assert_eq(sys.lines.size(), 1, "it lingers after the utterance")
	sys.tick(0.36 + Tuning.f(&"noise.caption_linger_s") + 0.01)
	assert_eq(sys.lines.size(), 0)
	sys.on_voice(8, "frame", 2, _header(Vector2(15, 10), true), Vector2(10, 10), 1.0)
	sys.on_voice(9, "frame", 2, _header(Vector2(15, 10), false, true), Vector2(10, 10), 1.0)
	var shown: Array[Dictionary] = sys.visible_lines()
	assert_eq(str(shown[0]["text"]), "[voice, on the line] (spoken)")
	var phone: Variant = shown[0]["bearing"]
	assert_true(phone == null, "a phone line has no direction")
	assert_eq(str(shown[1]["text"]), "[voice] (spoken)")
	var dry: Variant = shown[1]["bearing"]
	assert_true(dry == null, "a dry channel has no direction")
	for h: Dictionary in sys.history:
		assert_true(str(h["key"]).begins_with("caption.voice"), "voice lines come only from their keys")
